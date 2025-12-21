# Monitoring Homelab - K3s on Proxmox Carrick

Infrastructure-as-Code for deploying a K3s monitoring cluster using **Terraform → Ansible → ArgoCD** pipeline.

## ⚠️ CRITICAL: GitOps Workflow MANDATORY

**READ THIS FIRST**: `/home/monit_homelab/GITOPS-WORKFLOW.md`

**ALWAYS use GitOps workflow for ALL changes:**
1. ✅ Commit to git FIRST
2. ✅ Push to GitHub
3. ✅ Deploy via Terraform/ArgoCD (automation)
4. ❌ NEVER manual kubectl apply
5. ❌ NEVER manual infrastructure changes

## Overview

This repository deploys a lightweight K3s Kubernetes cluster in an LXC container for monitoring infrastructure (Prometheus, Grafana, VictoriaMetrics, Coroot, MCP servers, etc.). The monitoring cluster is isolated from production on a separate Proxmox host and network.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Deployment Pipeline                                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. Terraform   → Create LXC infrastructure                      │
│ 2. Ansible     → Configure OS + install K3s                     │
│ 3. Semaphore   → Web UI for Ansible playbooks                   │
│ 4. ArgoCD      → Deploy monitoring stack (GitOps)               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Proxmox Carrick (10.30.0.10)                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ K3s Monitor LXC (VMID: 200, IP: 10.30.0.20)                │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ Debian 13 (unprivileged LXC)                           │ │ │
│ │ │ - nesting=true, keyctl=true, fuse=true                 │ │ │
│ │ │                                                         │ │ │
│ │ │ ┌─────────────────────────────────────────────────────┐ │ │ │
│ │ │ │ K3s Cluster                                         │ │ │ │
│ │ │ │ - Prometheus, Grafana, VictoriaMetrics, etc.        │ │ │ │
│ │ │ │ - Managed by ArgoCD (GitOps)                        │ │ │ │
│ │ │ └─────────────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ Network: vmbr0 (10.30.0.0/24)                                   │
│ Storage: Kerrier ZFS pool                                       │
└─────────────────────────────────────────────────────────────────┘

Management: iac LXC (10.10.0.175) - Runs Terraform, Ansible, Semaphore
Production: Proxmox Ruapehu (10.10.0.10) - Separate cluster
```

### Key Features

- **Clean Separation**: Terraform (infra) → Ansible (config) → ArgoCD (apps)
- **Network Isolation**: Monitoring on 10.30.0.0/24, Production on 10.10.0.0/24
- **Semaphore UI**: Visual interface for Ansible playbook execution
- **GitOps**: ArgoCD manages monitoring stack deployment
- **Idempotent**: All playbooks safe to re-run

## Prerequisites

### Required Tools
- **Terraform** >= 1.10 (already installed on iac LXC)
- **Ansible** >= 2.19 (already installed on iac LXC)
- **kubectl** >= 1.34 (already installed on iac LXC)
- **SSH Access**: To Proxmox Carrick (root@10.30.0.10)

### Access Requirements
- Proxmox Carrick credentials
- Network access to 10.30.0.0/24

## Quick Start

### 1. Setup Credentials

```bash
cd /home/monit_homelab

# Create credentials file from template
cp .env.monitoring.example .env.monitoring

# Edit with your actual passwords
vim .env.monitoring
# Set: TF_VAR_monitoring_proxmox_password
# Set: TF_VAR_lxc_root_password

# Secure the file
chmod 600 .env.monitoring

# Source credentials
source .env.monitoring
```

### 2. Deploy Infrastructure (Terraform)

```bash
cd terraform/lxc-only

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=lxc.plan

# Apply (creates LXC container only)
terraform apply lxc.plan

# Wait 30-60 seconds for LXC to boot
sleep 30

# Verify SSH access
ssh root@10.30.0.20 'hostname'
# Should output: k3s-monitor
```

### 3. Configure LXC (Ansible)

```bash
cd /home/monit_homelab/ansible

# Source credentials (if not already done)
source /home/monit_homelab/.env.monitoring

# Test connectivity
ansible -i inventory/monitoring.yml k3s_monitor -m ping

# Run base configuration playbook
ansible-playbook -i inventory/monitoring.yml playbooks/01-base-lxc.yml

# Expected output:
# - /dev/kmsg fixed and persistent
# - Kernel modules loaded (br_netfilter, overlay)
# - Required packages installed
```

### 4. Install K3s (Ansible)

```bash
# Run K3s installation playbook
ansible-playbook -i inventory/monitoring.yml playbooks/02-k3s-install.yml

# Expected output:
# - K3s installed with disabled components (traefik, servicelb, local-storage)
# - Kubeconfig retrieved to ~/.kube/monitoring-k3s.yaml
# - Cluster status displayed
```

### 5. Verify K3s Cluster

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/monitoring-k3s.yaml

# Check cluster
kubectl get nodes -o wide
# Expected: 1 node (k3s-monitor) in Ready state

kubectl get pods -A
# Expected: kube-system pods running (coredns, metrics-server, etc.)

kubectl cluster-info
# Expected: Kubernetes control plane at https://10.30.0.20:6443
```

### 6. Install Semaphore (Optional UI)

```bash
# Follow the detailed guide
cat semaphore/README.md

# Quick install:
SEMAPHORE_VERSION="v2.16.0"
wget -O /tmp/semaphore.tar.gz \
  "https://github.com/semaphoreui/semaphore/releases/download/${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.tar.gz"
sudo tar -xzf /tmp/semaphore.tar.gz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/semaphore

# Create user and directories
sudo useradd -r -s /bin/false -d /var/lib/semaphore semaphore
sudo mkdir -p /etc/semaphore /var/lib/semaphore
sudo chown -R semaphore:semaphore /var/lib/semaphore

# Run interactive setup
cd /etc/semaphore
sudo semaphore setup

# Follow prompts, then create systemd service (see semaphore/README.md)

# Access UI: http://10.10.0.175:3000
```

### 7. Run Verification

```bash
cd /home/monit_homelab

# Run comprehensive verification
./verify-deployment.sh

# Checks:
# - Terraform state
# - LXC existence and SSH access
# - /dev/kmsg fix
# - K3s service status
# - Kubeconfig validity
# - Semaphore UI (if installed)
```

## Repository Structure

```
/home/monit_homelab/
├── terraform/
│   ├── lxc-only/                    # Clean Terraform (infrastructure only)
│   │   ├── versions.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── main.tf                  # LXC definition (NO provisioners!)
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── monitoring-lxc/              # OLD approach (to be archived)
│
├── ansible/
│   ├── inventory/
│   │   └── monitoring.yml           # K3s LXC inventory
│   ├── playbooks/
│   │   ├── 01-base-lxc.yml         # Base OS config (/dev/kmsg, packages, etc.)
│   │   └── 02-k3s-install.yml       # K3s installation + kubeconfig retrieval
│   └── group_vars/                  # (Future use)
│
├── semaphore/
│   └── README.md                    # Semaphore installation guide
│
├── .env.monitoring.example          # Credentials template
├── verify-deployment.sh             # Deployment verification script
├── README.md                        # This file
├── PHASES.md                        # Deployment roadmap
└── DEPLOYMENT_SUMMARY.md            # Architecture summary
```

## Deployment Workflow

### Step-by-Step Process

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Credentials Setup                                        │
│    source .env.monitoring                                   │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Terraform (Infrastructure)                               │
│    cd terraform/lxc-only                                    │
│    terraform init && terraform apply                        │
│    → Creates LXC container on Proxmox Carrick               │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Ansible Playbook 1 (Base Config)                        │
│    cd ansible                                                │
│    ansible-playbook -i inventory/monitoring.yml \           │
│      playbooks/01-base-lxc.yml                              │
│    → /dev/kmsg fix, kernel modules, packages                │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Ansible Playbook 2 (K3s Install)                        │
│    ansible-playbook -i inventory/monitoring.yml \           │
│      playbooks/02-k3s-install.yml                           │
│    → K3s installation, kubeconfig retrieval                 │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Semaphore (Optional)                                     │
│    Follow semaphore/README.md                               │
│    → Web UI for Ansible playbooks                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Verification                                              │
│    ./verify-deployment.sh                                   │
│    → Comprehensive checks                                    │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Phase 2: ArgoCD Deployment (Future)                     │
│    Deploy monitoring stack via GitOps                       │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Details

### Terraform Variables

See `terraform/lxc-only/variables.tf` for full list. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `lxc_vmid` | 200 | LXC container ID |
| `lxc_hostname` | k3s-monitor | Container hostname |
| `lxc_ip` | 10.30.0.20/24 | Static IP address |
| `lxc_cores` | 2 | CPU cores |
| `lxc_memory` | 4096 | RAM in MB |
| `lxc_disk_size` | 30 | Disk size in GB |

### Ansible Inventory

See `ansible/inventory/monitoring.yml`. Key variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `k3s_version` | stable | K3s version to install |
| `k3s_server_ip` | 10.30.0.20 | K3s API server address |
| `k3s_disable_components` | traefik, servicelb, local-storage | Components to disable |
| `kubeconfig_dest` | ~/.kube/monitoring-k3s.yaml | Kubeconfig save location |

## Troubleshooting

### LXC Container Issues

```bash
# Check LXC status on Proxmox
ssh root@10.30.0.10 "pct list | grep 200"

# Check LXC configuration
ssh root@10.30.0.10 "pct config 200"

# View LXC logs
ssh root@10.30.0.10 "journalctl -u pve-container@200"

# Restart LXC
ssh root@10.30.0.10 "pct stop 200 && pct start 200"
```

### Ansible Connection Issues

```bash
# Test connectivity
ansible -i ansible/inventory/monitoring.yml k3s_monitor -m ping

# Check SSH access
ssh root@10.30.0.20 'hostname'

# Verify password environment variable
echo $ANSIBLE_LXC_PASSWORD

# Run playbook with verbose output
ansible-playbook -i ansible/inventory/monitoring.yml playbooks/01-base-lxc.yml -vvv
```

### K3s Issues

```bash
# SSH to K3s LXC
ssh root@10.30.0.20

# Check K3s service
systemctl status k3s
journalctl -u k3s -f

# Verify /dev/kmsg exists (CRITICAL)
ls -la /dev/kmsg
systemctl status conf-kmsg

# Check K3s nodes
k3s kubectl get nodes
k3s kubectl get pods -A

# Reinstall K3s (if needed)
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik,servicelb,local-storage \
  --flannel-backend=host-gw \
  --write-kubeconfig-mode=644
```

### Kubeconfig Issues

```bash
# Check kubeconfig exists
ls -la ~/.kube/monitoring-k3s.yaml

# Verify server address (should be 10.30.0.20, not 127.0.0.1)
grep server ~/.kube/monitoring-k3s.yaml

# Test connection
kubectl --kubeconfig ~/.kube/monitoring-k3s.yaml get nodes

# Re-fetch kubeconfig
ssh root@10.30.0.20 'cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/monitoring-k3s.yaml
sed -i 's|https://127.0.0.1:6443|https://10.30.0.20:6443|g' ~/.kube/monitoring-k3s.yaml
chmod 600 ~/.kube/monitoring-k3s.yaml
```

## Maintenance

### Updating K3s

```bash
# SSH to K3s LXC
ssh root@10.30.0.20

# Update to latest stable
curl -sfL https://get.k3s.io | sh -

# Or specific version
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.5+k3s1 sh -

# Restart K3s
systemctl restart k3s

# Verify
k3s --version
k3s kubectl get nodes
```

### Destroying Infrastructure

```bash
cd /home/monit_homelab/terraform/lxc-only

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Manual cleanup if needed
ssh root@10.30.0.10 "pct stop 200 && pct destroy 200"
```

### Backing Up Configuration

```bash
# Backup Terraform state
cp terraform/lxc-only/terraform.tfstate terraform/lxc-only/terraform.tfstate.backup-$(date +%Y%m%d)

# Backup kubeconfig
cp ~/.kube/monitoring-k3s.yaml ~/.kube/monitoring-k3s.yaml.backup-$(date +%Y%m%d)

# Backup Semaphore database (if installed)
sudo cp /var/lib/semaphore/semaphore.db /var/lib/semaphore/semaphore.db.backup-$(date +%Y%m%d)
```

## Network Configuration

### IP Allocation

| Resource | IP | Network | Purpose |
|----------|----|---------| --------|
| Carrick Proxmox | 10.30.0.10 | 10.30.0.0/24 | Hypervisor |
| Gateway | 10.30.0.1 | 10.30.0.0/24 | Network gateway |
| K3s Monitor | 10.30.0.20 | 10.30.0.0/24 | Monitoring cluster |
| TrueNAS | 10.30.0.120 | 10.30.0.0/24 | Storage (Phase 2) |
| iac LXC | 10.10.0.175 | 10.10.0.0/24 | Management/Terraform/Ansible |

### Network Isolation

- **Monitoring Network**: 10.30.0.0/24 (Carrick)
- **Production Network**: 10.10.0.0/24 (Ruapehu)
- **Routing**: iac LXC can reach both networks for management

## Architecture Decisions

### Why Terraform → Ansible → ArgoCD?

- **Separation of Concerns**: Each tool does what it's best at
  - Terraform: Infrastructure provisioning
  - Ansible: OS configuration and software installation
  - ArgoCD: Application deployment and GitOps
- **Clean**: No embedded scripts in Terraform
- **Idempotent**: Safe to re-run any step
- **Maintainable**: Clear boundaries between layers

### Why Semaphore?

- **UI Access**: Non-terminal users can run playbooks
- **Audit Trail**: Track who ran what and when
- **Scheduling**: Cron-like execution for maintenance tasks
- **Visual Feedback**: Real-time playbook output

### Why Disable Traefik/ServiceLB/Local-Storage?

- **Flexibility**: Use preferred ingress/LB/storage solutions
- **Resource Savings**: ~200MB RAM saved
- **Consistency**: Match production cluster setup
- **Best Practices**: Dedicated components per use case

## Next Steps (Phase 2)

After infrastructure is ready:

1. **Deploy Monitoring Stack via ArgoCD**
   - Prometheus for metrics collection
   - VictoriaMetrics for long-term storage (200GB NFS)
   - VictoriaLogs for log aggregation (500GB NFS)
   - Grafana for visualization
   - AlertManager for alerting

2. **Configure Storage**
   - Setup NFS mounts from TrueNAS (10.30.0.120)
   - Configure PersistentVolumes for VictoriaMetrics/Logs

3. **Configure Scrape Targets**
   - Proxmox metrics (Ruapehu + Carrick)
   - Kubernetes metrics (Talos cluster)
   - Application metrics (Plex, etc.)
   - OPNsense firewall metrics

4. **Setup External Access**
   - Cloudflare Tunnel for Grafana
   - Configure dashboards
   - Setup alert notifications (Slack/Discord)

See `PHASES.md` for complete roadmap.

## References

- **K3s Documentation**: https://docs.k3s.io
- **Proxmox LXC**: https://pve.proxmox.com/wiki/Linux_Container
- **Terraform Proxmox Provider**: https://registry.terraform.io/providers/bpg/proxmox
- **Ansible Documentation**: https://docs.ansible.com/
- **Semaphore UI**: https://docs.semaphoreui.com/
- **Production Homelab**: /home/prod_homelab
- **Plan File**: /root/.claude/plans/resilient-stargazing-dusk.md

## Support

- **Issues**: File issues or questions in this repository
- **Production Reference**: /home/prod_homelab/infrastructure
- **Proxmox Carrick**: ssh root@10.30.0.10
- **K3s Monitor**: ssh root@10.30.0.20
