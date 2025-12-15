# ============================================================================
# Dual Proxmox Provider Configuration
# ============================================================================
# This configuration maintains references to both Proxmox instances:
# - "production" provider points to Ruapehu (10.10.0.10) - production homelab
# - "monitoring" provider points to Carrick (10.30.0.10) - monitoring cluster
# Resources in this project use the "monitoring" provider explicitly.
# ============================================================================

# Production Proxmox (Ruapehu) - Reference only
# This provider exists for potential cross-cluster operations
# Uses TF_VAR_production_proxmox_* environment variables
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

# Monitoring Proxmox (Carrick) - Active deployment target
# All resources in this configuration use this provider
# Uses TF_VAR_monitoring_proxmox_* environment variables
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
