# ============================================================================
# K3s Monitoring Cluster - LXC Deployment (Documented Best Practices)
# ============================================================================
# This configuration deploys a single-node K3s cluster on Proxmox Carrick
# following documented best practices for K3s on LXC.
#
# Architecture:
# - Host: Proxmox Carrick (10.30.0.10)
# - Platform: Debian 13 LXC container (unprivileged)
# - K3s: Latest stable with required LXC features
# - Network: Single NIC on vmbr0 (10.30.0.0/24)
#
# Critical LXC Requirements for K3s:
# - features.nesting = true  (allows container to run containers)
# - features.keyctl = true   (required for K3s security features)
# - features.fuse = true     (required for overlayfs/container storage)
# - /dev/kmsg symlink        (kubelet needs kernel message buffer)
#
# Reference: Standard documented approach for K3s on Proxmox LXC
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

  description = "K3s monitoring cluster - LXC with nesting/keyctl/fuse + /dev/kmsg fix"

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

  # Initialization (hostname, network, DNS, root password)
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

    # Set root password for SSH access
    user_account {
      password = var.monitoring_proxmox_password
    }
  }

  # Container Features (ALL required for K3s)
  features {
    nesting = true # Allows container to run containers (pods)
    keyctl  = true # Required for K3s security subsystem
    fuse    = true # Required for overlayfs/container storage layers
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
# Configure SSH Access (before remote-exec)
# ============================================================================
resource "null_resource" "configure_ssh" {
  depends_on = [proxmox_virtual_environment_container.k3s_monitoring]

  triggers = {
    container_id = proxmox_virtual_environment_container.k3s_monitoring.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuring SSH for password authentication..."
      sleep 10

      # Enable password authentication for root
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct exec 200 -- bash -c 'mkdir -p /etc/ssh/sshd_config.d && \
         echo \"PermitRootLogin yes\" > /etc/ssh/sshd_config.d/99-permit-root.conf && \
         echo \"PasswordAuthentication yes\" >> /etc/ssh/sshd_config.d/99-permit-root.conf && \
         systemctl restart ssh'"

      echo "Waiting for SSH to be ready..."
      sleep 5
    EOT
  }
}

# ============================================================================
# Provision K3s (documented best practice via pct exec)
# ============================================================================
resource "null_resource" "provision_k3s" {
  depends_on = [null_resource.configure_ssh]

  triggers = {
    container_id = proxmox_virtual_environment_container.k3s_monitoring.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Provisioning K3s with documented best practices (nesting/keyctl/fuse + /dev/kmsg fix)..."

      # Execute documented provisioning steps via pct exec
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        root@10.30.0.10 \
        "pct exec 200 -- bash -c '
          # 1. CRITICAL: Fix /dev/kmsg (required for Kubelet in LXC)
          if [ ! -e /dev/kmsg ]; then ln -s /dev/console /dev/kmsg; fi

          # 2. Create persistent kmsg fix script
          cat > /usr/local/bin/conf-kmsg.sh <<\"INNEREOF\"
#!/bin/sh
if [ ! -e /dev/kmsg ]; then ln -s /dev/console /dev/kmsg; fi
INNEREOF
          chmod +x /usr/local/bin/conf-kmsg.sh

          # 3. Create systemd service
          cat > /etc/systemd/system/conf-kmsg.service <<\"INNEREOF\"
[Unit]
Description=Make sure /dev/kmsg exists
[Service]
Type=simple
ExecStart=/usr/local/bin/conf-kmsg.sh
[Install]
WantedBy=multi-user.target
INNEREOF
          systemctl enable --now conf-kmsg.service

          echo \"✓ /dev/kmsg fix installed\"

          # 4. Install required packages
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates nfs-common iptables

          echo \"✓ Packages installed\"

          # 5. Install K3s
          curl -sfL https://get.k3s.io | sh -s - --disable traefik --disable servicelb --disable local-storage --flannel-backend=host-gw --write-kubeconfig-mode=644

          # 6. Wait for K3s to be ready
          timeout 120 bash -c \"until k3s kubectl get nodes 2>/dev/null | grep -q Ready; do echo Waiting for K3s...; sleep 5; done\"

          # 7. Fix kubeconfig server address
          sed -i \"s|https://127.0.0.1:6443|https://10.30.0.20:6443|g\" /etc/rancher/k3s/k3s.yaml

          # 8. Create root kubeconfig
          mkdir -p /root/.kube
          cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
          chmod 600 /root/.kube/config

          # 9. Verify
          k3s kubectl get nodes
          echo \"✓ K3s installation complete\"
        '"
    EOT
  }
}

# ============================================================================
# Retrieve Kubeconfig
# ============================================================================
resource "null_resource" "retrieve_kubeconfig" {
  depends_on = [null_resource.provision_k3s]

  triggers = {
    k3s_complete = null_resource.provision_k3s.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube

      # Retrieve kubeconfig via direct SSH to container
      sshpass -p '${var.monitoring_proxmox_password}' ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        root@${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")} \
        'cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/monitoring-k3s.yaml || \
      echo "Warning: Could not retrieve kubeconfig via SSH, trying via Proxmox host..." && \
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
    # K3s has been provisioned via documented remote-exec approach
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
