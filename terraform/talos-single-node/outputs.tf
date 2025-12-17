# ============================================================================
# Terraform Outputs - Monitoring Cluster
# ============================================================================

# Create generated directory
resource "null_resource" "create_generated_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/generated"
  }
}

# Write kubeconfig to file
resource "local_file" "kubeconfig" {
  depends_on = [talos_cluster_kubeconfig.this, null_resource.create_generated_dir]

  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/generated/kubeconfig"
  file_permission = "0600"
}

# Write talosconfig to file
resource "local_file" "talosconfig" {
  depends_on = [talos_machine_secrets.this, null_resource.create_generated_dir]

  content         = yamlencode(talos_machine_secrets.this.client_configuration)
  filename        = "${path.module}/generated/talosconfig"
  file_permission = "0600"
}

# Cluster Information
output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = local.cluster_endpoint
}

# Monitoring Node
output "monitoring_node_ip" {
  description = "Monitoring node IP address"
  value       = var.monitoring_node.ip
}

output "monitoring_node_vm_id" {
  description = "Monitoring node VM ID"
  value       = proxmox_virtual_environment_vm.monitoring_node.vm_id
}

# Kubeconfig
output "kubeconfig_path" {
  description = "Path to generated kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "talosconfig_path" {
  description = "Path to generated talosconfig file"
  value       = local_file.talosconfig.filename
}

# Network Information
output "cilium_lb_ip_pool" {
  description = "Cilium LoadBalancer IP pool"
  value       = var.cilium_lb_ip_pool
}

output "network_summary" {
  description = "Network configuration summary"
  value = {
    network = local.network.network
    bridge  = local.network.bridge
    gateway = local.network.gateway
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for cluster access"
  value       = <<-EOT
    # Export kubeconfig
    export KUBECONFIG=${local_file.kubeconfig.filename}

    # Check cluster nodes
    kubectl get nodes

    # Check Talos cluster health
    talosctl --talosconfig ${local_file.talosconfig.filename} health

    # Check Cilium status
    kubectl get pods -n kube-system -l k8s-app=cilium

    # View LoadBalancer IP pool
    kubectl get ciliumloadbalancerippool

    # Next steps:
    # 1. Bootstrap Infisical operator (Helm)
    # 2. Register cluster with prod ArgoCD
    # 3. Deploy monitoring apps via ArgoCD
  EOT
}
