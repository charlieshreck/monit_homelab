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

provider "helm" {
  kubernetes = {
    config_path = "${path.module}/generated/kubeconfig"
  }
}

provider "kubectl" {
  config_path      = "${path.module}/generated/kubeconfig"
  load_config_file = true
}

provider "kubernetes" {
  config_path = "${path.module}/generated/kubeconfig"
}
