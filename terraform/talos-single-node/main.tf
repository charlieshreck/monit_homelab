# ============================================================================
# Talos Single-Node Monitoring Cluster
# ============================================================================
# Single control-plane node with allowSchedulingOnControlPlanes=true
# Deployed on Proxmox Pihanga (10.10.0.20) - Ryzen 5 7640HS, 28GB RAM
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
    floating  = 0  # Disable balloon - single node needs stable memory
  }

  bios = "ovmf"

  efi_disk {
    datastore_id = var.monitoring_proxmox_storage
    file_format  = "raw"
    type         = "4m"
  }

  # NIC 0: Production network (management, ArgoCD, API server, Cilium LB)
  network_device {
    bridge      = var.network_bridge
    mac_address = local.node_config.mac_address
    model       = "virtio"
  }

  # NIC 1: Monitoring network (direct L2 NFS path to TrueNAS-HDD)
  network_device {
    bridge      = var.network_bridge_monit
    mac_address = local.monitoring_node_monit_mac
    model       = "virtio"
  }

  # Boot disk on Mauao ZFS pool (500GB P310 SSD)
  disk {
    datastore_id = var.monitoring_proxmox_storage
    interface    = "scsi0"
    size         = local.node_config.disk
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Data disk for monitoring storage (Mauao ZFS pool - shared with boot disk)
  # Pihanga has a single 500GB NVMe, so data disk is on same pool
  disk {
    datastore_id = var.monitoring_proxmox_storage
    interface    = "scsi1"
    size         = 200  # 200GB for VictoriaMetrics/Logs (Pihanga has 500GB total)
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Talos ISO (only used for initial boot, then removed)
  cdrom {
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
        # Enable virtio_balloon for memory ballooning support
        kernel = {
          modules = [
            { name = "virtio_balloon" }
          ]
        }

        network = {
          hostname = local.node_config.name
          interfaces = [
            {
              # NIC 0: Production network (management, ArgoCD, API server)
              # Use deviceSelector by MAC for reliable matching (ens18 on Proxmox virtio)
              deviceSelector = {
                hardwareAddr = local.node_config.mac_address
              }
              addresses = ["${local.node_config.ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.network.gateway
                }
              ]
            },
            {
              # NIC 1: Monitoring network (direct L2 NFS to TrueNAS-HDD)
              # Use deviceSelector by MAC for reliable matching (ens19 on Proxmox virtio)
              deviceSelector = {
                hardwareAddr = local.monitoring_node_monit_mac
              }
              addresses = ["${local.monit_network.ip}/24"]
            }
          ]
          nameservers = var.dns_servers
        }

        kubelet = {
          extraArgs = {
            rotate-server-certificates = "true"
          }
        }

        # Machine certificate SANs (for API server certificate)
        certSANs = [
          local.node_config.ip,
          local.node_config.name
        ]

        install = {
          image           = "ghcr.io/siderolabs/installer:${var.talos_version}"
          disk            = "/dev/sda"
          wipe            = false
          bootloader      = true
          extraKernelArgs = []
        }

        # Mount second disk for monitoring data storage
        disks = [
          {
            device = "/dev/sdb"
            partitions = [
              {
                mountpoint = "/var/mnt/monitoring-data"
              }
            ]
          }
        ]

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

# Automatically approve pending CSRs
resource "null_resource" "approve_csrs" {
  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/generated/kubeconfig
      echo "Waiting for CSRs to appear..."
      for i in {1..30}; do
        pending=$(kubectl get csr --no-headers 2>/dev/null | grep Pending | wc -l || echo 0)
        if [ "$pending" -gt 0 ]; then
          echo "Approving $pending pending CSR(s)..."
          kubectl certificate approve $(kubectl get csr --no-headers | grep Pending | awk '{print $1}')
          echo "CSRs approved"
          break
        fi
        sleep 5
      done
    EOT
  }

  depends_on = [
    talos_cluster_kubeconfig.this,
  ]
}

# Wait for cluster health
data "talos_cluster_health" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [local.node_config.ip]
  worker_nodes         = [] # No separate worker nodes
  endpoints            = [local.node_config.ip]

  depends_on = [
    null_resource.approve_csrs,
  ]
}
