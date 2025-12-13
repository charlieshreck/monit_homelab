# ============================================================================
# K3s Monitoring Cluster - LXC Deployment with IaC Provisioning
# ============================================================================
# This configuration deploys a single-node K3s cluster on Proxmox Carrick
# using a version-controlled provisioning script (pure IaC approach).
#
# Architecture:
# - Host: Proxmox Carrick (10.30.0.10)
# - Platform: Debian 13 LXC container (unprivileged)
# - K3s: Latest stable, LXC-optimized settings
# - Network: Single NIC on vmbr0 (10.30.0.0/24)
# - Provisioning: provision-k3s.sh (version controlled, executed via pct exec)
#
# IaC Implementation:
# - provision-k3s.sh script is version-controlled and defines all provisioning steps
# - Container rebooted after creation to ensure network initialization
# - Script executed via Proxmox pct exec for deterministic provisioning
# - Maintains full IaC compliance with version-controlled configuration
#
# Note: LXC containers have limitations with cloud-init compared to VMs.
# This approach uses a version-controlled shell script for true IaC while
# working within LXC constraints.
# ============================================================================

# ============================================================================
# Proxmox Host Preparation (Load Kernel Modules)
# ============================================================================
resource "null_resource" "proxmox_kernel_modules" {
  provider = null

  triggers = {
    proxmox_host = var.monitoring_proxmox_host
  }

  provisioner "local-exec" {
    command = <<-EOT
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        'modprobe br_netfilter && modprobe overlay && \
         echo "br_netfilter" > /etc/modules-load.d/k3s.conf && \
         echo "overlay" >> /etc/modules-load.d/k3s.conf && \
         echo "Kernel modules loaded for K3s"'
    EOT
  }
}

# ============================================================================
# LXC Container Resource
# ============================================================================
resource "proxmox_virtual_environment_container" "k3s_monitoring" {
  provider  = proxmox.monitoring
  node_name = var.monitoring_proxmox_node
  vm_id     = var.lxc_vmid

  description = "K3s monitoring cluster - cloud-init provisioned"

  # Operating System
  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  # Unprivileged container for better security
  unprivileged = true

  # CPU Configuration
  cpu {
    cores = var.lxc_cores
  }

  # Memory Configuration
  memory {
    dedicated = var.lxc_memory
  }

  # Disk Configuration
  disk {
    datastore_id = var.monitoring_proxmox_storage
    size         = var.lxc_disk_size
  }

  # Network Configuration
  network_interface {
    name = "eth0"
  }

  # Basic Initialization (hostname, network, DNS only)
  # Note: LXC containers don't support cloud-init user_data like VMs
  # Provisioning is handled via the provision-k3s.sh script
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
  }

  # Container Features
  features {
    nesting = true # Required for K3s containers
  }

  # Start on boot
  startup {
    order      = 100
    up_delay   = 30 # Give cloud-init time to run
    down_delay = 10
  }

  started = true

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }

  depends_on = [null_resource.proxmox_kernel_modules]
}

# ============================================================================
# Reboot Container (Required for LXC network initialization)
# ============================================================================
resource "null_resource" "reboot_container" {
  depends_on = [proxmox_virtual_environment_container.k3s_monitoring]

  triggers = {
    container_id = proxmox_virtual_environment_container.k3s_monitoring.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Rebooting container to apply network configuration..."
      sleep 10  # Wait for container to fully start

      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct reboot 200"

      # Wait for container to come back online
      sleep 20
    EOT
  }
}

# ============================================================================
# Provision K3s (IaC via version-controlled script)
# ============================================================================
resource "null_resource" "provision_k3s" {
  depends_on = [null_resource.reboot_container]

  triggers = {
    container_id = proxmox_virtual_environment_container.k3s_monitoring.id
    script_hash  = filemd5("${path.module}/provision-k3s.sh")
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Provisioning K3s via version-controlled script..."

      # Copy provisioning script to container
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "cat > /tmp/provision-k3s.sh" < ${path.module}/provision-k3s.sh

      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct push 200 /tmp/provision-k3s.sh /tmp/provision-k3s.sh"

      # Execute provisioning script
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct exec 200 -- bash /tmp/provision-k3s.sh"
    EOT
  }
}

# ============================================================================
# Wait for K3s Installation
# ============================================================================
resource "null_resource" "wait_for_k3s" {
  depends_on = [null_resource.provision_k3s]

  triggers = {
    provision_complete = null_resource.provision_k3s.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for K3s to be fully ready..."
      sleep 30
    EOT
  }
}

# ============================================================================
# Retrieve Kubeconfig
# ============================================================================
resource "null_resource" "retrieve_kubeconfig" {
  depends_on = [null_resource.wait_for_k3s]

  triggers = {
    k3s_complete = null_resource.wait_for_k3s.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube

      # Retrieve kubeconfig via pct exec (cloud-init configured SSH)
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct exec 200 -- cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/monitoring-k3s.yaml

      # Set proper permissions
      chmod 600 ~/.kube/monitoring-k3s.yaml

      echo "Kubeconfig saved to ~/.kube/monitoring-k3s.yaml"
    EOT
  }
}

# ============================================================================
# Local Kubeconfig Reference File
# ============================================================================
resource "local_file" "kubeconfig" {
  depends_on = [null_resource.retrieve_kubeconfig]

  filename = "${path.module}/kubeconfig"
  content  = <<-EOT
    # Kubeconfig Location
    # K3s has been provisioned via cloud-init (cloud-init.yaml)
    # Kubeconfig is stored at: ~/.kube/monitoring-k3s.yaml
    #
    # Usage:
    #   export KUBECONFIG=~/.kube/monitoring-k3s.yaml
    #   kubectl get nodes
    #
    # Cluster Endpoint: https://10.30.0.20:6443
  EOT

  file_permission = "0644"
}
