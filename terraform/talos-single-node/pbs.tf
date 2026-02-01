# ============================================================================
# Proxmox Backup Server (PBS) VM
# ============================================================================
# PBS provides VM/LXC snapshot-level backups as a disaster recovery layer.
# Running on Pihanga allows backing up Ruapehu VMs from a separate host.
#
# NOTE: PBS installation is interactive. After terraform apply:
#   1. Open VM console in Proxmox UI
#   2. Complete PBS installer (set root password, email, etc.)
#   3. Configure datastore to use NFS mount
# ============================================================================

locals {
  pbs_config = {
    vmid   = 101
    name   = "pbs"
    ip     = "10.10.0.151"
    cores  = 2
    memory = 2048  # 2GB RAM
    disk   = 32    # 32GB boot disk
  }
}

# Download official PBS ISO
resource "proxmox_virtual_environment_download_file" "pbs_iso" {
  provider     = proxmox.monitoring
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.monitoring_proxmox_node

  url       = "https://enterprise.proxmox.com/iso/proxmox-backup-server_4.1-1.iso"
  file_name = "proxmox-backup-server_4.1-1.iso"

  overwrite           = false
  overwrite_unmanaged = true
}

# PBS VM
resource "proxmox_virtual_environment_vm" "pbs" {
  provider    = proxmox.monitoring
  name        = local.pbs_config.name
  description = "Proxmox Backup Server - DR backups for Ruapehu VMs"
  node_name   = var.monitoring_proxmox_node
  vm_id       = local.pbs_config.vmid

  cpu {
    cores = local.pbs_config.cores
    type  = "host"
  }

  memory {
    dedicated = local.pbs_config.memory
  }

  # Boot disk
  disk {
    datastore_id = var.monitoring_proxmox_storage
    interface    = "scsi0"
    size         = local.pbs_config.disk
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Network
  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # PBS ISO for installation
  cdrom {
    file_id   = proxmox_virtual_environment_download_file.pbs_iso.id
    interface = "ide2"
  }

  # BIOS settings
  bios = "seabios"

  operating_system {
    type = "l26"
  }

  # Start VM for installation
  on_boot = true
  started = true

  # Ignore CD-ROM changes after initial install
  lifecycle {
    ignore_changes = [
      cdrom,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_download_file.pbs_iso,
  ]
}

# ============================================================================
# Outputs
# ============================================================================

output "pbs_vmid" {
  description = "PBS VM ID"
  value       = local.pbs_config.vmid
}

output "pbs_ip" {
  description = "PBS server IP address (configure during install)"
  value       = local.pbs_config.ip
}

output "pbs_web_ui" {
  description = "PBS Web UI URL (after installation)"
  value       = "https://${local.pbs_config.ip}:8007"
}

output "pbs_install_steps" {
  description = "PBS installation steps"
  value       = <<-EOT
    PBS Installation Steps:

    1. Open Pihanga Proxmox UI → VM 101 → Console

    2. Complete PBS installer:
       - Accept EULA
       - Select target disk (local disk)
       - Country/Timezone
       - Password: (your choice)
       - Email: (your email)
       - Network:
         - IP: ${local.pbs_config.ip}/24
         - Gateway: ${var.monitoring_gateway}
         - DNS: 10.10.0.1
       - Install

    3. After reboot, access: https://${local.pbs_config.ip}:8007
       - Login: root

    4. Add NFS datastore:
       - SSH to PBS: ssh root@${local.pbs_config.ip}
       - mkdir -p /mnt/pbs-datastore
       - echo "10.20.0.103:/mnt/Taupo/pbs /mnt/pbs-datastore nfs defaults,_netdev 0 0" >> /etc/fstab
       - mount -a
       - In PBS UI: Administration → Storage → Add Directory
         - Name: pbs-datastore
         - Path: /mnt/pbs-datastore

    5. Add PBS storage to Ruapehu:
       - Ruapehu UI → Datacenter → Storage → Add → PBS
       - ID: pbs-pihanga
       - Server: ${local.pbs_config.ip}
       - Datastore: pbs-datastore
       - Username: root@pam
       - Get fingerprint from PBS Dashboard

    6. Create backup jobs on Ruapehu:
       - Datacenter → Backup → Add
       - Storage: pbs-pihanga
       - VMs: 100, 450, 451
       - Schedule: sun 02:00
  EOT
}
