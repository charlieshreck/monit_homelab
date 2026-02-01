# ============================================================================
# Local Path Provisioner - Storage for monitoring cluster
# ============================================================================
# Deployed via Terraform to ensure storage is available before ArgoCD apps
# ============================================================================

resource "kubernetes_namespace" "local_path_storage" {
  metadata {
    name = "local-path-storage"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  depends_on = [
    data.talos_cluster_health.this,
  ]
}

resource "kubernetes_service_account" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-service-account"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_role" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-role"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }
}

resource "kubernetes_role_binding" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-bind"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.local_path_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.local_path_provisioner.metadata[0].name
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-role"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "persistentvolumeclaims", "configmaps", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-bind"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.local_path_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.local_path_provisioner.metadata[0].name
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_deployment" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "local-path-provisioner"
      }
    }

    template {
      metadata {
        labels = {
          app = "local-path-provisioner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.local_path_provisioner.metadata[0].name

        container {
          name  = "local-path-provisioner"
          image = "rancher/local-path-provisioner:v0.0.28"

          command = ["local-path-provisioner", "--debug", "start", "--config", "/etc/config/config.json"]

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config/"
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.local_path_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_storage_class" "local_path" {
  metadata {
    name = "local-path"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "rancher.io/local-path"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}

resource "kubernetes_config_map" "local_path_config" {
  metadata {
    name      = "local-path-config"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  data = {
    "config.json" = jsonencode({
      nodePathMap = [
        {
          node  = "DEFAULT_PATH_FOR_NON_LISTED_NODES"
          paths = ["/var/mnt/monitoring-data/local-path-provisioner"]
        }
      ]
    })

    "setup" = <<-EOT
      #!/bin/sh
      set -eu
      mkdir -m 0777 -p "$VOL_DIR"
    EOT

    "teardown" = <<-EOT
      #!/bin/sh
      set -eu
      rm -rf "$VOL_DIR"
    EOT

    "helperPod.yaml" = <<-EOT
      apiVersion: v1
      kind: Pod
      metadata:
        name: helper-pod
      spec:
        priorityClassName: system-node-critical
        tolerations:
          - key: node.kubernetes.io/disk-pressure
            operator: Exists
            effect: NoSchedule
        containers:
        - name: helper-pod
          image: busybox
          imagePullPolicy: IfNotPresent
    EOT
  }
}

# ============================================================================
# Monitoring Namespace
# ============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  depends_on = [
    data.talos_cluster_health.this,
  ]
}

# ============================================================================
# Production Cluster Credentials Secret
# ============================================================================
# Secret for Prometheus to scrape metrics from production cluster

resource "kubernetes_secret" "production_cluster_credentials" {
  metadata {
    name      = "production-cluster-credentials"
    namespace = "monitoring"
  }

  data = {
    "ca.crt" = file("/home/prod_homelab/infrastructure/terraform/generated/ca.crt")
    "token"  = file("/home/prod_homelab/infrastructure/terraform/generated/prometheus-token")
  }

  depends_on = [
    kubernetes_namespace.monitoring,
  ]
}

# ============================================================================
# NFS Storage from TrueNAS-HDD (Tekapo pool)
# ============================================================================
# Victoria metrics/logs use NFS from TrueNAS-HDD at 10.20.0.103
# Datasets created on Tekapo RAIDZ1 pool (5x 500GB EVOs = ~2TB usable)

locals {
  truenas_hdd_ip = "10.20.0.103"
}

# NFS PV for VictoriaMetrics
resource "kubernetes_persistent_volume" "victoria_metrics_nfs" {
  metadata {
    name = "victoria-metrics-nfs-pv"
  }

  spec {
    capacity = {
      storage = "500Gi"
    }
    access_modes = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "nfs"

    persistent_volume_source {
      nfs {
        server = local.truenas_hdd_ip
        path   = "/mnt/Tekapo/victoria-metrics"
      }
    }
  }
}

# NFS PV for VictoriaLogs
resource "kubernetes_persistent_volume" "victoria_logs_nfs" {
  metadata {
    name = "victoria-logs-nfs-pv"
  }

  spec {
    capacity = {
      storage = "1000Gi"
    }
    access_modes = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "nfs"

    persistent_volume_source {
      nfs {
        server = local.truenas_hdd_ip
        path   = "/mnt/Tekapo/victoria-logs"
      }
    }
  }
}

# NFS Storage Class (manual binding)
resource "kubernetes_storage_class" "nfs" {
  metadata {
    name = "nfs"
  }

  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"
}

# ============================================================================
# PVCs for VictoriaMetrics and VictoriaLogs
# ============================================================================
# Bound to NFS PVs on TrueNAS-HDD Tekapo pool

resource "kubernetes_persistent_volume_claim" "victoria_metrics" {
  metadata {
    name      = "victoria-metrics-storage"
    namespace = "monitoring"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "500Gi"
      }
    }
    storage_class_name = "nfs"
    volume_name        = kubernetes_persistent_volume.victoria_metrics_nfs.metadata[0].name
  }

  wait_until_bound = false

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_persistent_volume.victoria_metrics_nfs,
  ]
}

resource "kubernetes_persistent_volume_claim" "victoria_logs" {
  metadata {
    name      = "victoria-logs-storage"
    namespace = "monitoring"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1000Gi"
      }
    }
    storage_class_name = "nfs"
    volume_name        = kubernetes_persistent_volume.victoria_logs_nfs.metadata[0].name
  }

  wait_until_bound = false

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_persistent_volume.victoria_logs_nfs,
  ]
}

# ============================================================================
# Coroot Namespace
# ============================================================================

resource "kubernetes_namespace" "coroot" {
  metadata {
    name = "coroot"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  depends_on = [
    data.talos_cluster_health.this,
  ]
}

# ============================================================================
# NOTE: Coroot Operator manages its own PVCs
# ============================================================================
# The Coroot operator automatically creates PVCs for ClickHouse and server
# storage. Pre-created PVCs are not used and remain in Pending state.
# Operator-managed PVCs:
# - data-coroot-clickhouse-shard-0-0 (100Gi) - eBPF traces/profiles/logs
# - data-coroot-clickhouse-keeper-* (3x10Gi) - Keeper coordination data
# - data-coroot-coroot-0 (10Gi) - Server configuration and cache
