#!/bin/bash
# ============================================================================
# K3s Monitoring Cluster - Provisioning Script
# ============================================================================
# This script provisions K3s on a Debian 13 LXC container
# Managed by Terraform - version controlled IaC approach
# ============================================================================

set -e  # Exit on error
set -x  # Debug output

echo "========================================="
echo "K3s Provisioning Script - Starting"
echo "========================================="

# ============================================================================
# System Preparation
# ============================================================================
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "Installing required packages..."
apt-get install -y \
  curl \
  wget \
  ca-certificates \
  nfs-common \
  iptables

# ============================================================================
# Network and System Readiness
# ============================================================================
echo "Waiting for network and system initialization..."
sleep 15

# ============================================================================
# K3s Installation
# ============================================================================
echo "Installing K3s with LXC-optimized settings..."

export INSTALL_K3S_EXEC="server \
  --disable=traefik \
  --disable=servicelb \
  --disable=local-storage \
  --flannel-backend=host-gw \
  --write-kubeconfig-mode=644"

curl -sfL https://get.k3s.io | sh -s -

# ============================================================================
# Wait for K3s API Server
# ============================================================================
echo "Waiting for K3s API server to be ready..."
timeout 120 bash -c 'until k3s kubectl get nodes 2>/dev/null | grep -q Ready; do
  echo "Waiting for K3s API...";
  sleep 5;
done'

# ============================================================================
# Kubeconfig Configuration
# ============================================================================
echo "Configuring kubeconfig..."

# Fix kubeconfig server address (replace 127.0.0.1 with actual IP)
sed -i 's|https://127.0.0.1:6443|https://10.30.0.20:6443|g' /etc/rancher/k3s/k3s.yaml
chmod 644 /etc/rancher/k3s/k3s.yaml

# Create root kubeconfig
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config

# ============================================================================
# Verification
# ============================================================================
echo "Verifying K3s installation..."
k3s kubectl get nodes
k3s kubectl get pods -A

# ============================================================================
# Completion Marker
# ============================================================================
echo "K3s installation complete - $(date)" >> /var/log/cloud-init-k3s.log
echo "K3s installation complete - $(date)"

echo "========================================="
echo "K3s Provisioning Script - Complete"
echo "========================================="
