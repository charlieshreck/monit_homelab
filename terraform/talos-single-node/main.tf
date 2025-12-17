# ============================================================================
# Talos Single-Node Monitoring Cluster
# ============================================================================
# Single control-plane node with allowSchedulingOnControlPlanes=true
# Deployed on Proxmox Carrick (10.30.0.10)
# ============================================================================

# Generate custom Talos image schematic ID with extensions
data "external" "talos_image" {
  program = ["bash", "${path.module}/../../scripts/generate-talos-image.sh"]

  query = {
    talos_version = var.talos_version
  }
}

# Download and upload custom Talos ISO to Proxmox
resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  provider     = proxmox.monitoring
  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.monitoring_proxmox_node

  # Use custom factory image with extensions
  url = "https://factory.talos.dev/image/${data.external.talos_image.result.schematic_id}/${data.external.talos_image.result.version}/nocloud-amd64.iso"

  file_name           = "talos-${data.external.talos_image.result.version}-${substr(data.external.talos_image.result.schematic_id, 0, 8)}-nocloud-amd64.iso"
  overwrite           = false
  overwrite_unmanaged = true
  checksum            = null
  checksum_algorithm  = null
}

# ============================================================================
# Monitoring Node VM (Single Control Plane with Workloads)
# ============================================================================
resource "proxmox_virtual_environment_vm" "monitoring_node" {
  provider    = proxmox.monitoring
  name        = local.node_config.name
  description = "Talos Linux monitoring cluster - single node"
  node_name   = var.monitoring_proxmox_node
  vm_id       = local.node_config.vmid

  cpu {
    cores = local.node_config.cores
    type  = "host"
  }

  memory {
    dedicated = local.node_config.memory
  }

  bios = "ovmf"

  efi_disk {
    datastore_id = var.monitoring_proxmox_storage
    file_format  = "raw"
    type         = "4m"
  }

  # Single NIC on vmbr0 (management network)
  network_device {
    bridge      = var.network_bridge
    mac_address = local.node_config.mac_address
    model       = "virtio"
  }

  # Boot disk on Kerrier ZFS pool
  disk {
    datastore_id = var.monitoring_proxmox_storage
    interface    = "scsi0"
    size         = local.node_config.disk
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Talos ISO
  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    interface = "ide2"
  }

  serial_device {}

  on_boot = true
  started = true

  operating_system {
    type = "l26"
  }

  agent {
    enabled = false
  }

  lifecycle {
    ignore_changes = [
      cdrom,
    ]
  }
}

# ============================================================================
# Talos Cluster Bootstrap
# ============================================================================

# Generate Talos machine secrets
resource "talos_machine_secrets" "this" {}

# Generate control plane machine configuration
data "talos_machine_configuration" "monitoring_node" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      cluster = {
        # CRITICAL: Enable workload scheduling on control plane (single-node cluster)
        allowSchedulingOnControlPlanes = true

        # Monitoring cluster network
        network = {
          cni = {
            name = "none" # Cilium will be installed via Helm
          }
        }

        # Cilium replaces kube-proxy
        proxy = {
          disabled = true
        }

        # Cluster discovery
        discovery = {
          enabled = true
          registries = {
            kubernetes = {
              disabled = false
            }
            service = {
              disabled = false
            }
          }
        }
      }

      machine = {
        network = {
          hostname = local.node_config.name
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${local.node_config.ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.network.gateway
                }
              ]
            }
          ]
          nameservers = var.dns_servers
        }

        kubelet = {
          extraArgs = {
            rotate-server-certificates = "true"
          }
        }

        install = {
          image           = "ghcr.io/siderolabs/installer:${var.talos_version}"
          disk            = "/dev/sda"
          wipe            = false
          bootloader      = true
          extraKernelArgs = []
        }

        # Enable KubePrism for reliable kube-apiserver access
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
    })
  ]
}

# Apply control plane configuration
resource "talos_machine_configuration_apply" "monitoring_node" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.monitoring_node.machine_configuration
  node                        = local.node_config.ip

  depends_on = [
    proxmox_virtual_environment_vm.monitoring_node,
  ]
}

# Bootstrap Talos cluster (single node)
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.node_config.ip

  depends_on = [
    talos_machine_configuration_apply.monitoring_node,
  ]
}

# Retrieve kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.node_config.ip

  depends_on = [
    talos_machine_bootstrap.this,
  ]
}

# Wait for cluster health
data "talos_cluster_health" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [local.node_config.ip]
  worker_nodes         = [] # No separate worker nodes
  endpoints            = [local.node_config.ip]

  depends_on = [
    talos_machine_bootstrap.this,
  ]
}
