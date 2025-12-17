provider "proxmox" {
  alias    = "monitoring"
  endpoint = "https://${var.monitoring_proxmox_host}:8006"
  username = var.monitoring_proxmox_user
  password = var.monitoring_proxmox_password
  insecure = true

  ssh {
    agent    = false
    username = "root"
    password = var.monitoring_proxmox_password
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
