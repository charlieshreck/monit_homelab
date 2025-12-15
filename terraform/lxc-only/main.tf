# ============================================================================
# K3s Monitoring LXC - Infrastructure Only
# ============================================================================
# This configuration ONLY provisions infrastructure.
# Configuration management is handled by Ansible playbooks.
#
# Key Requirements for K3s in LXC:
# - features.nesting = true  (container-in-container support)
# - features.keyctl = true   (K3s security subsystem)
# - features.fuse = true     (overlayfs/container storage)
#
# Architecture:
# - Terraform: Provisions LXC container (THIS FILE)
# - Ansible:   Configures OS and installs K3s
# - ArgoCD:    Deploys monitoring stack
# ============================================================================

resource "proxmox_virtual_environment_container" "k3s_monitoring" {
  provider  = proxmox.monitoring
  node_name = var.monitoring_proxmox_node
  vm_id     = var.lxc_vmid

  description = "K3s monitoring cluster - Terraform (infra) + Ansible (config)"

  # Operating System
  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  # Unprivileged container for better security
  unprivileged = true

  # Resources
  cpu {
    cores = var.lxc_cores
  }

  memory {
    dedicated = var.lxc_memory
  }

  disk {
    datastore_id = var.monitoring_proxmox_storage
    size         = var.lxc_disk_size
  }

  # Network
  network_interface {
    name = "eth0"
  }

  # Initialization
  initialization {
    hostname = var.lxc_hostname

    ip_config {
      ipv4 {
        address = var.lxc_ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      password = var.lxc_root_password
    }
  }

  # K3s-required features
  features {
    nesting = true  # Allows running containers inside the LXC (pods)
    keyctl  = true  # Required for K3s security features
    fuse    = true  # Required for overlayfs and container storage
  }

  # Startup configuration
  startup {
    order      = 100
    up_delay   = 30
    down_delay = 10
  }

  started = true

  # Ignore changes to initialization after first creation
  # (Ansible manages configuration after this point)
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}
