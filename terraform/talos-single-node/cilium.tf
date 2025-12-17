# ============================================================================
# Cilium CNI Installation
# ============================================================================
# Deploys Cilium with L2 announcements for LoadBalancer services
# ============================================================================

# Wait for cluster API to be ready
resource "null_resource" "wait_for_cluster" {
  depends_on = [
    talos_machine_bootstrap.this,
    local_file.kubeconfig
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/generated/kubeconfig
      echo "Waiting for Kubernetes API..."
      timeout 600 bash -c 'until kubectl get --raw /healthz 2>/dev/null; do echo "Waiting..."; sleep 5; done'
      echo "✅ API ready!"
    EOT
  }

  triggers = {
    cluster_id = talos_machine_bootstrap.this.id
  }
}

# Install Cilium CNI via Helm
resource "helm_release" "cilium" {
  depends_on = [null_resource.wait_for_cluster]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.18.4"
  namespace  = "kube-system"
  timeout    = 900

  values = [yamlencode({
    ipam = {
      mode = "kubernetes"
    }
    k8sServiceHost       = var.monitoring_node.ip
    k8sServicePort       = 6443
    kubeProxyReplacement = true

    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK",
          "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER",
          "SETGID", "SETUID"
        ]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }

    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }

    l2announcements = {
      enabled            = true
      leaseDuration      = "3s"
      leaseRenewDeadline = "1s"
      leaseRetryPeriod   = "200ms"
    }

    # Use ens18 (eth0 on vmbr0) for L2 announcements
    devices = "ens18"

    externalIPs = {
      enabled = true
    }

    hubble = { enabled = false }
  })]
}

# Wait for Cilium pods to be ready
resource "null_resource" "wait_for_cilium" {
  depends_on = [helm_release.cilium]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/generated/kubeconfig
      echo "Waiting for Cilium pods to appear..."
      for i in {1..60}; do
        POD_COUNT=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | wc -l)
        if [ "$POD_COUNT" -gt 0 ]; then
          echo "Found $POD_COUNT Cilium pods, waiting for ready..."
          kubectl wait --for=condition=ready pod \
            -l k8s-app=cilium \
            -n kube-system \
            --timeout=600s
          echo "✅ Cilium operational"
          exit 0
        fi
        echo "Attempt $i/60: No Cilium pods yet..."
        sleep 5
      done
      echo "❌ Cilium pods never appeared"
      exit 1
    EOT
  }

  triggers = {
    helm_release_id = helm_release.cilium.id
  }
}

# Configure LoadBalancer IP Pool
resource "kubectl_manifest" "cilium_lb_ippool" {
  depends_on = [null_resource.wait_for_cilium]

  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "cilium-lb-pool"
    }
    spec = {
      blocks = var.cilium_lb_ip_pool
    }
  })
}

# Configure L2 Announcement Policy
resource "kubectl_manifest" "cilium_l2_announcement" {
  depends_on = [kubectl_manifest.cilium_lb_ippool]

  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata = {
      name = "l2-announcement-policy"
    }
    spec = {
      loadBalancerIPs = true
      nodeSelector = {
        matchExpressions = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "DoesNotExist"
          }
        ]
      }
    }
  })
}

# Restart Cilium for L2 policy application
resource "null_resource" "restart_cilium_for_l2" {
  depends_on = [kubectl_manifest.cilium_l2_announcement]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/generated/kubeconfig
      echo "Restarting Cilium to apply L2 announcement policies..."
      kubectl rollout restart daemonset cilium -n kube-system
      kubectl rollout status daemonset cilium -n kube-system --timeout=5m
      echo "✅ Cilium L2 announcements active"
    EOT
  }

  triggers = {
    l2_policy_id = kubectl_manifest.cilium_l2_announcement.id
  }
}

# Output Cilium status
output "cilium_status" {
  description = "Cilium CNI installation status"
  value       = "Cilium installed with L2 LoadBalancer support (IP pool: ${join(", ", [for block in var.cilium_lb_ip_pool : "${block.start}-${block.stop}"])})"
  depends_on  = [null_resource.restart_cilium_for_l2]
}
