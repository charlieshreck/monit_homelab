# ============================================================================
# Proxmox Providers
# ============================================================================

# Monitoring Proxmox (Carrick) - Active deployment target
provider "proxmox" {
  alias    = "monitoring"
  endpoint = var.monitoring_proxmox_host
  username = var.monitoring_proxmox_user
  password = var.monitoring_proxmox_password
  insecure = true

  ssh {
    agent    = false
    username = "root"
    password = var.monitoring_proxmox_password
  }
}

# Production Proxmox (Ruapehu) - Reference only (optional for future use)
provider "proxmox" {
  alias    = "production"
  endpoint = var.production_proxmox_host
  username = var.production_proxmox_user
  password = var.production_proxmox_password
  insecure = true

  ssh {
    agent    = false
    username = "root"
    password = var.production_proxmox_password
  }
}
