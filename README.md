# Monitoring Homelab - K3s on Proxmox Carrick

Infrastructure-as-Code for deploying a K3s monitoring cluster on Proxmox Carrick (10.30.0.10), separate from the production Proxmox Ruapehu.

## Overview

This repository deploys a lightweight K3s Kubernetes cluster in an LXC container for monitoring infrastructure (Prometheus, Grafana, Loki, etc.). The monitoring cluster is isolated from production on a separate Proxmox host and network.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Proxmox Carrick (10.30.0.10)                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ LXC Container (VMID: 200)                                   │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ Debian 13                                               │ │ │
│ │ │ Hostname: k3s-monitor                                   │ │ │
│ │ │ IP: 10.30.0.20/24                                       │ │ │
│ │ │ ┌─────────────────────────────────────────────────────┐ │ │ │
│ │ │ │ K3s v1.28.x                                         │ │ │ │
│ │ │ │ - No Traefik (use your own ingress)                │ │ │ │
│ │ │ │ - No ServiceLB (use MetalLB or similar)            │ │ │ │
│ │ │ │ - No local-storage (use Longhorn or similar)       │ │ │ │
│ │ │ └─────────────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ Network: vmbr0 (10.30.0.0/24)                                   │
│ Storage: Kerrier ZFS pool (483GB)                               │
└─────────────────────────────────────────────────────────────────┘

Production Proxmox Ruapehu (10.10.0.10) - Separate cluster
```

### Key Features

- **Network Isolation**: Monitoring on 10.30.0.0/24, Production on 10.10.0.0/24
- **Dual Provider Setup**: References both Proxmox instances in Terraform
- **LXC Container**: Lightweight, nested containers enabled for K3s
- **Minimal K3s**: Disabled Traefik, ServiceLB, local-storage for custom setup
- **GitOps Ready**: Deploy monitoring stack via Helm/Kustomize

## Discovered Configuration

### Proxmox Carrick Details

SSH into Carrick to verify configuration:

```bash
# SSH to Carrick
ssh root@10.30.0.10

# Node name
hostname
# Output: Carrick

# Storage pools
pvesm status
# Output:
# Kerrier   - ZFS pool (483GB total, 414GB available)
# local     - Directory (230GB total, 203GB available)

# Network bridges
ip link show | grep vmbr
# Output: vmbr0, vmbr1, vmbr2, vmbr3

# Network configuration
cat /etc/network/interfaces | grep -A 10 vmbr0
# vmbr0: 10.30.0.10/24, gateway 10.30.0.1

# Check Debian 13 template
pveam list local | grep debian-13
# Output: debian-13-standard_13.1-1_amd64.tar.zst (122MB)
```

## Prerequisites

1. **Terraform**: >= 1.9
2. **SSH Access**: To Proxmox Carrick (root@10.30.0.10)
3. **Proxmox Credentials**: Password for Carrick
4. **Network Access**: Can reach 10.30.0.0/24 network
5. **Tools**: `sshpass` for kubeconfig retrieval

Install prerequisites:

```bash
# Debian/Ubuntu
apt-get install -y terraform sshpass

# macOS
brew install terraform sshpass
```

## Setup Instructions

### 1. Clone Repository

```bash
cd /home
git clone https://github.com/charlieshreck/monit_homelab.git
cd monit_homelab/terraform/monitoring-lxc
```

### 2. Configure Credentials

**Option A: Environment Variables (Recommended)**

Create a credentials file:

```bash
# Create credentials file (gitignored)
cat > ~/.config/terraform/monitoring-creds.env << 'EOF'
# === Monitoring Proxmox Carrick ===
export TF_VAR_monitoring_proxmox_host="https://10.30.0.10:8006"
export TF_VAR_monitoring_proxmox_user="root@pam"
export TF_VAR_monitoring_proxmox_password="H4ckwh1z"
export TF_VAR_monitoring_proxmox_node="Carrick"
export TF_VAR_monitoring_proxmox_storage="Kerrier"

# === Production Proxmox Ruapehu (Reference) ===
export TF_VAR_production_proxmox_host="https://10.10.0.10:8006"
export TF_VAR_production_proxmox_user="root@pam"
export TF_VAR_production_proxmox_password="your-production-password"
export TF_VAR_production_proxmox_node="Ruapehu"
EOF

# Secure the file
chmod 600 ~/.config/terraform/monitoring-creds.env

# Source credentials
source ~/.config/terraform/monitoring-creds.env
```

**Option B: terraform.tfvars (Less secure)**

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars

# NEVER commit terraform.tfvars to git!
```

### 3. Review Configuration

```bash
# Review variables
cat variables.tf

# Key settings:
# - LXC IP: 10.30.0.20/24
# - VMID: 200
# - Resources: 2 vCPU, 4GB RAM, 30GB disk
# - K3s: Latest stable, minimal components
```

### 4. Initialize Terraform

```bash
cd /home/monit_homelab/terraform/monitoring-lxc

# Initialize providers
terraform init

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive
```

### 5. Plan Deployment

```bash
# Generate execution plan
terraform plan -out=monitoring.plan

# Review the plan carefully
# Expected resources:
# - 1x LXC container (proxmox_virtual_environment_container)
# - 3x null_resource (wait, k3s install, kubeconfig)
# - 1x local_file (kubeconfig reference)
```

### 6. Deploy Infrastructure

```bash
# Apply the plan
terraform apply monitoring.plan

# Deployment takes ~5-10 minutes:
# 1. Create LXC container (1 min)
# 2. Wait for boot (30 sec)
# 3. Install K3s (2-3 min)
# 4. Retrieve kubeconfig (30 sec)
```

### 7. Verify Deployment

```bash
# Check Terraform outputs
terraform output

# Export kubeconfig
export KUBECONFIG=~/.kube/monitoring-k3s.yaml

# Verify cluster
kubectl get nodes
# Expected: 1 node (k3s-monitor) in Ready state

kubectl get pods -A
# Expected: kube-system pods (coredns, metrics-server, etc.)

# SSH to container
ssh root@10.30.0.20

# Inside container - check K3s
k3s kubectl get nodes
systemctl status k3s
```

## Post-Deployment

### Install Monitoring Stack

Deploy Prometheus, Grafana, and related tools:

```bash
# Example: Kube-Prometheus-Stack via Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=secure-password
```

### Configure Ingress

Since Traefik is disabled, install your preferred ingress:

```bash
# Example: Nginx Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### Add Persistent Storage

Since local-storage is disabled, add a CSI:

```bash
# Example: Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

## Network Configuration

### IP Allocation

| Resource | IP | Network | Purpose |
|----------|----|---------| --------|
| Carrick Proxmox | 10.30.0.10 | 10.30.0.0/24 | Hypervisor |
| Gateway | 10.30.0.1 | 10.30.0.0/24 | Network gateway |
| K3s Monitor | 10.30.0.20 | 10.30.0.0/24 | Monitoring cluster |
| Available | 10.30.0.21-254 | 10.30.0.0/24 | Future use |

### Network Isolation

- **Monitoring**: 10.30.0.0/24 (Carrick)
- **Production**: 10.10.0.0/24 (Ruapehu)
- **No overlap**: Ensures complete isolation

## Troubleshooting

### LXC Container Won't Start

```bash
# Check Proxmox logs
ssh root@10.30.0.10 "pct list"
ssh root@10.30.0.10 "pct status 200"
ssh root@10.30.0.10 "journalctl -u pve-container@200"
```

### K3s Installation Failed

```bash
# SSH to container
ssh root@10.30.0.20

# Check K3s logs
journalctl -u k3s -f

# Manual K3s check
systemctl status k3s
k3s kubectl get nodes

# Reinstall K3s
curl -sfL https://get.k3s.io | sh -
```

### Kubeconfig Not Working

```bash
# Verify kubeconfig location
ls -la ~/.kube/monitoring-k3s.yaml

# Check server address (should be 10.30.0.20, not 127.0.0.1)
grep server ~/.kube/monitoring-k3s.yaml

# Test connection
kubectl --kubeconfig ~/.kube/monitoring-k3s.yaml get nodes
```

### Can't SSH to Container

```bash
# Check container networking
ssh root@10.30.0.10 "pct exec 200 -- ip addr show"

# Test ping
ping 10.30.0.20

# Check firewall
ssh root@10.30.0.10 "pct exec 200 -- iptables -L"
```

## Maintenance

### Updating K3s

```bash
# SSH to container
ssh root@10.30.0.20

# Update K3s to latest
curl -sfL https://get.k3s.io | sh -

# Or specific version
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.5+k3s1 sh -

# Restart K3s
systemctl restart k3s
```

### Destroying Infrastructure

```bash
cd /home/monit_homelab/terraform/monitoring-lxc

# Plan destruction
terraform plan -destroy -out=destroy.plan

# Apply destruction
terraform destroy

# Manual cleanup if needed
ssh root@10.30.0.10 "pct destroy 200"
```

## Security Considerations

1. **Credentials**: Use environment variables, not terraform.tfvars
2. **SSH Keys**: Add your public key to lxc_ssh_public_key variable
3. **Network**: Consider firewall rules for 10.30.0.0/24
4. **Updates**: Regularly update LXC container and K3s
5. **Secrets**: Use Kubernetes Secrets or external secret management

## Architecture Decisions

### Why LXC Instead of VM?

- **Lighter**: ~100MB RAM overhead vs ~500MB for VM
- **Faster**: Boots in seconds
- **Efficient**: Shared kernel with host
- **Sufficient**: K3s works fine in unprivileged LXC with nesting

### Why Disable Traefik/ServiceLB/Local-Storage?

- **Flexibility**: Use your preferred ingress/LB/storage
- **Consistency**: Match production cluster setup
- **Resource savings**: ~200MB RAM saved
- **Best practices**: Dedicated components per use case

### Why Separate Proxmox?

- **Isolation**: Monitoring failures don't affect production
- **Network**: Separate subnet prevents conflicts
- **Resource**: Dedicated hardware for monitoring workloads
- **Security**: Monitoring has different access patterns

## References

- **K3s Documentation**: https://docs.k3s.io
- **Proxmox LXC**: https://pve.proxmox.com/wiki/Linux_Container
- **Terraform Proxmox Provider**: https://registry.terraform.io/providers/bpg/proxmox
- **Production Homelab**: /home/prod_homelab

## Support

- **Issues**: https://github.com/charlieshreck/monit_homelab/issues
- **Production Reference**: /home/prod_homelab/infrastructure/terraform
- **Proxmox Carrick**: ssh root@10.30.0.10
