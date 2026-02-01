# ============================================================================
# Proxmox Backup Server (PBS) LXC Container
# ============================================================================
# PBS provides VM/LXC snapshot-level backups as a disaster recovery layer.
# Running on Pihanga allows backing up Ruapehu VMs from a separate host.
#
# NOTE: After creation, configure the datastore to use TrueNAS-HDD NFS:
#   1. Add NFS storage to Pihanga: Datacenter → Storage → Add → NFS
#      - ID: truenas-pbs
#      - Server: 10.20.0.103
#      - Export: /mnt/Taupo/pbs
#      - Content: VZDump backup file
#   2. In PBS UI: Add datastore pointing to /mnt/truenas-pbs
# ============================================================================

locals {
  pbs_config = {
    vmid   = 101
    name   = "pbs"
    ip     = "10.10.0.151"
    cores  = 2
    memory = 2048  # 2GB RAM
    swap   = 512
    disk   = 32    # 32GB root disk (for PBS system + local cache)
  }
}

# Download Debian template for PBS
resource "proxmox_virtual_environment_download_file" "pbs_template" {
  provider     = proxmox.monitoring
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.monitoring_proxmox_node

  url       = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"
  file_name = "debian-12-standard_12.7-1_amd64.tar.zst"

  overwrite           = false
  overwrite_unmanaged = true
}

# PBS LXC Container
resource "proxmox_virtual_environment_container" "pbs" {
  provider    = proxmox.monitoring
  node_name   = var.monitoring_proxmox_node
  vm_id       = local.pbs_config.vmid
  description = "Proxmox Backup Server - DR backups for Ruapehu VMs"

  initialization {
    hostname = local.pbs_config.name

    ip_config {
      ipv4 {
        address = "${local.pbs_config.ip}/24"
        gateway = var.monitoring_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys     = []
      password = var.monitoring_proxmox_ssh_password  # Initial root password
    }
  }

  cpu {
    cores = local.pbs_config.cores
  }

  memory {
    dedicated = local.pbs_config.memory
    swap      = local.pbs_config.swap
  }

  disk {
    datastore_id = var.monitoring_proxmox_storage
    size         = local.pbs_config.disk
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.pbs_template.id
    type             = "debian"
  }

  features {
    nesting = true
  }

  start_on_boot = true
  started       = true
  unprivileged  = false  # Privileged for NFS mount access

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_download_file.pbs_template,
  ]
}

# Install PBS in the container
resource "null_resource" "pbs_install" {
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "",
      "echo 'Waiting for container to be ready...'",
      "sleep 15",
      "",
      "echo 'Installing PBS in container ${local.pbs_config.vmid}...'",
      "pct exec ${local.pbs_config.vmid} -- bash -c '",
      "  set -e",
      "  ",
      "  # Add Proxmox PBS repository",
      "  echo \"deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription\" > /etc/apt/sources.list.d/pbs.list",
      "  ",
      "  # Add Proxmox GPG key",
      "  apt-get update",
      "  apt-get install -y wget gnupg",
      "  wget -q https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg",
      "  ",
      "  # Update and install PBS + NFS",
      "  apt-get update",
      "  DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-backup-server nfs-common",
      "  ",
      "  # Create mount point for NFS datastore",
      "  mkdir -p /mnt/pbs-datastore",
      "  ",
      "  # Add NFS mount to fstab (will be mounted manually or on reboot)",
      "  echo \"10.20.0.103:/mnt/Taupo/pbs /mnt/pbs-datastore nfs defaults,_netdev 0 0\" >> /etc/fstab",
      "  ",
      "  # Try to mount NFS",
      "  mount /mnt/pbs-datastore || echo \"NFS mount failed - configure manually if needed\"",
      "  ",
      "  # Enable and start PBS services",
      "  systemctl enable proxmox-backup-proxy proxmox-backup",
      "  systemctl start proxmox-backup-proxy proxmox-backup",
      "  ",
      "  echo \"PBS installation complete!\"",
      "  echo \"Access PBS at: https://${local.pbs_config.ip}:8007\"",
      "'",
    ]

    connection {
      type     = "ssh"
      user     = "root"
      password = var.monitoring_proxmox_ssh_password
      host     = var.monitoring_proxmox_host
    }
  }

  depends_on = [
    proxmox_virtual_environment_container.pbs,
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "pbs_ip" {
  description = "PBS server IP address"
  value       = local.pbs_config.ip
}

output "pbs_web_ui" {
  description = "PBS Web UI URL"
  value       = "https://${local.pbs_config.ip}:8007"
}

output "pbs_post_install_steps" {
  description = "Steps to complete PBS setup"
  value       = <<-EOT
    PBS Post-Installation Steps:

    1. Access PBS UI: https://${local.pbs_config.ip}:8007
       - Login: root (password from terraform.tfvars)

    2. Create datastore in PBS:
       - Administration → Storage/Disks → Directory
       - Add: /mnt/pbs-datastore
       - Name: pbs-datastore

    3. Add Ruapehu as remote (to backup its VMs):
       - On Ruapehu Proxmox UI: Datacenter → Storage → Add → PBS
         - ID: pbs-pihanga
         - Server: ${local.pbs_config.ip}
         - Datastore: pbs-datastore
         - Username: root@pam
         - Fingerprint: (get from PBS UI)

    4. Create backup schedule on Ruapehu:
       - Datacenter → Backup → Add
       - Storage: pbs-pihanga
       - VMs: 100 (IAC), 450 (Plex), 451 (UniFi)
       - Schedule: Sunday 02:00

    5. (Optional) Decommission old PBS on Ruapehu (VM 101)
  EOT
}
