provider "proxmox" {
  alias     = "monitoring"
  endpoint  = "https://${var.monitoring_proxmox_host}:8006"
  api_token = "${var.monitoring_proxmox_token_id}=${var.monitoring_proxmox_token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    password = var.monitoring_proxmox_ssh_password
  }
}

provider "talos" {}

# NOTE: helm, kubectl, and kubernetes providers removed.
# K8s resources are now managed exclusively by ArgoCD.
# See cilium.tf, infisical.tf, storage.tf for bootstrap instructions.
