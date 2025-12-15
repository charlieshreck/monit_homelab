#!/bin/bash
# ============================================================================
# Monitoring Infrastructure Verification Script
# ============================================================================
# This script verifies that all components of the monitoring infrastructure
# are deployed and functioning correctly.
#
# Usage:
#   ./verify-deployment.sh
# ============================================================================

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Monitoring Infrastructure Verification                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# 1. Terraform Deployment
# ============================================================================
echo "1. Checking Terraform deployment..."

if [ -f "/home/monit_homelab/terraform/lxc-only/terraform.tfstate" ]; then
    cd /home/monit_homelab/terraform/lxc-only
    if terraform output -json > /dev/null 2>&1; then
        check_pass "Terraform state valid"
        LXC_IP=$(terraform output -raw lxc_ip 2>/dev/null || echo "10.30.0.20")
    else
        check_fail "Terraform state invalid"
    fi
else
    check_fail "Terraform state file not found"
fi

# ============================================================================
# 2. LXC Container
# ============================================================================
echo ""
echo "2. Checking LXC container..."

if ssh root@10.30.0.10 "pct list | grep -q 200" 2>/dev/null; then
    check_pass "LXC 200 exists on Proxmox Carrick"
else
    check_fail "LXC 200 not found"
fi

if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@10.30.0.20 'hostname' > /dev/null 2>&1; then
    check_pass "SSH access working to 10.30.0.20"
    HOSTNAME=$(ssh -o StrictHostKeyChecking=no root@10.30.0.20 'hostname' 2>/dev/null)
    echo "   Hostname: ${HOSTNAME}"
else
    check_fail "SSH access failed to 10.30.0.20"
fi

# ============================================================================
# 3. Base Configuration
# ============================================================================
echo ""
echo "3. Checking base configuration..."

if ssh -o StrictHostKeyChecking=no root@10.30.0.20 'test -e /dev/kmsg' 2>/dev/null; then
    check_pass "/dev/kmsg exists"
else
    check_fail "/dev/kmsg missing (critical for K3s)"
fi

if ssh -o StrictHostKeyChecking=no root@10.30.0.20 'systemctl is-active conf-kmsg' > /dev/null 2>&1; then
    check_pass "conf-kmsg service active"
else
    check_fail "conf-kmsg service not active"
fi

# ============================================================================
# 4. K3s Cluster
# ============================================================================
echo ""
echo "4. Checking K3s cluster..."

if ssh -o StrictHostKeyChecking=no root@10.30.0.20 'systemctl is-active k3s' > /dev/null 2>&1; then
    check_pass "K3s service active"
else
    check_fail "K3s service not running"
fi

if [ -f "$HOME/.kube/monitoring-k3s.yaml" ]; then
    check_pass "Kubeconfig exists at ~/.kube/monitoring-k3s.yaml"

    export KUBECONFIG=$HOME/.kube/monitoring-k3s.yaml
    if kubectl get nodes > /dev/null 2>&1; then
        check_pass "K3s cluster accessible from control node"
        echo ""
        echo "   Cluster nodes:"
        kubectl get nodes -o wide 2>/dev/null | sed 's/^/   /'
    else
        check_fail "K3s cluster not accessible (check kubeconfig)"
    fi

    if kubectl get pods -A 2>/dev/null | grep -q "Running"; then
        check_pass "K3s pods running"
        RUNNING_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        echo "   Running pods: ${RUNNING_PODS}"
    else
        check_fail "No K3s pods running"
    fi
else
    check_fail "Kubeconfig not found at ~/.kube/monitoring-k3s.yaml"
fi

# ============================================================================
# 5. Semaphore
# ============================================================================
echo ""
echo "5. Checking Semaphore..."

if systemctl is-active semaphore > /dev/null 2>&1; then
    check_pass "Semaphore service active"
else
    check_fail "Semaphore not running (may not be installed yet)"
fi

if curl -s http://10.10.0.175:3000 > /dev/null 2>&1; then
    check_pass "Semaphore UI accessible at http://10.10.0.175:3000"
else
    check_fail "Semaphore UI not accessible"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Verification Complete                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Access Points:"
echo "  - K3s LXC SSH: ssh root@10.30.0.20"
echo "  - K3s cluster: export KUBECONFIG=~/.kube/monitoring-k3s.yaml && kubectl get nodes"
echo "  - Semaphore UI: http://10.10.0.175:3000"
echo ""
