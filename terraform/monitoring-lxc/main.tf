# ============================================================================
# K3s Monitoring Cluster - LXC Deployment
# ============================================================================
# This configuration deploys a single-node K3s cluster on Proxmox Carrick
# for monitoring infrastructure (Prometheus, Grafana, etc.)
#
# Architecture:
# - Host: Proxmox Carrick (10.30.0.10)
# - Platform: Debian 13 LXC container
# - K3s: Latest stable, no Traefik/ServiceLB/Local-Storage
# - Network: Single NIC on vmbr0 (10.30.0.0/24)
# ============================================================================

# ============================================================================
# LXC Container Resource
# ============================================================================
resource "proxmox_virtual_environment_container" "k3s_monitoring" {
  provider  = proxmox.monitoring
  node_name = var.monitoring_proxmox_node
  vm_id     = var.lxc_vmid

  description = "K3s monitoring cluster - single node"

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

  # Hostname
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

    # SSH key configuration (if provided)
    dynamic "user_account" {
      for_each = var.ssh_public_key != "" ? [1] : []
      content {
        keys     = [var.ssh_public_key]
        password = var.root_password != "" ? var.root_password : null
      }
    }
  }

  # Container Features
  features {
    nesting = true # Required for running containers in LXC (K3s needs this)
  }

  # Start on boot
  startup {
    order      = 100
    up_delay   = 10
    down_delay = 10
  }

  started = true

  lifecycle {
    ignore_changes = [
      # Ignore changes to these after initial creation
      initialization,
    ]
  }
}

# ============================================================================
# Wait for Container to be Ready
# ============================================================================
resource "null_resource" "wait_for_container" {
  depends_on = [proxmox_virtual_environment_container.k3s_monitoring]

  provisioner "local-exec" {
    command = "sleep 30" # Wait for container to fully boot
  }
}

# ============================================================================
# K3s Installation
# ============================================================================
resource "null_resource" "install_k3s" {
  depends_on = [null_resource.wait_for_container]

  # Trigger reinstall if K3s version changes
  triggers = {
    k3s_version        = var.k3s_version
    container_id       = proxmox_virtual_environment_container.k3s_monitoring.id
    disable_components = join(",", var.k3s_disable_components)
  }

  # SSH connection to LXC container
  connection {
    type     = "ssh"
    user     = "root"
    password = var.monitoring_proxmox_password
    host     = trimprefix(trimsuffix(var.lxc_ip, "/24"), "/") # Extract IP from CIDR
    timeout  = "5m"
  }

  # Install prerequisites and K3s
  provisioner "remote-exec" {
    inline = [
      "set -e",

      # Update system and install prerequisites
      "echo '==> Updating system packages...'",
      "apt-get update",
      "apt-get install -y curl wget",

      # Install K3s
      "echo '==> Installing K3s...'",
      "export INSTALL_K3S_VERSION='${var.k3s_version}'",
      "export INSTALL_K3S_EXEC='server --disable ${join(" --disable ", var.k3s_disable_components)}'",
      "curl -sfL https://get.k3s.io | sh -",

      # Wait for K3s to be ready
      "echo '==> Waiting for K3s to be ready...'",
      "timeout 120 bash -c 'until k3s kubectl get nodes | grep -q Ready; do sleep 5; done'",

      # Fix kubeconfig server address (replace 127.0.0.1 with actual IP)
      "echo '==> Fixing kubeconfig server address...'",
      "sed -i 's|https://127.0.0.1:6443|https://${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}:6443|g' /etc/rancher/k3s/k3s.yaml",

      # Set proper permissions
      "chmod 644 /etc/rancher/k3s/k3s.yaml",

      "echo '==> K3s installation complete!'",
      "k3s kubectl get nodes",
    ]
  }
}

# ============================================================================
# Retrieve Kubeconfig
# ============================================================================
resource "null_resource" "retrieve_kubeconfig" {
  depends_on = [null_resource.install_k3s]

  triggers = {
    k3s_install = null_resource.install_k3s.id
  }

  # SSH connection to retrieve kubeconfig
  connection {
    type     = "ssh"
    user     = "root"
    password = var.monitoring_proxmox_password
    host     = trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")
    timeout  = "2m"
  }

  # Download kubeconfig to local machine
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube
      sshpass -p '${var.monitoring_proxmox_password}' scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}:/etc/rancher/k3s/k3s.yaml \
        ~/.kube/monitoring-k3s.yaml
      chmod 600 ~/.kube/monitoring-k3s.yaml
    EOT
  }
}

# ============================================================================
# Local Kubeconfig File (for Terraform module output)
# ============================================================================
resource "local_file" "kubeconfig" {
  depends_on = [null_resource.retrieve_kubeconfig]

  filename = "${path.module}/kubeconfig"
  content  = "# Kubeconfig is stored at ~/.kube/monitoring-k3s.yaml\n# Use: export KUBECONFIG=~/.kube/monitoring-k3s.yaml\n"

  file_permission = "0644"
}
