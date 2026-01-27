# Monitoring Homelab - Talos Linux on Proxmox Carrick

Infrastructure-as-Code for deploying a Talos Linux monitoring cluster using **Terraform + ArgoCD** pipeline.

## GitOps Workflow MANDATORY

**READ THIS FIRST**: `/home/monit_homelab/GITOPS-WORKFLOW.md`

**ALWAYS use GitOps workflow for ALL changes:**
1. Commit to git FIRST
2. Push to GitHub
3. Deploy via Terraform/ArgoCD (automation)
4. NEVER manual kubectl apply
5. NEVER manual infrastructure changes

## Overview

This repository deploys a Talos Linux Kubernetes cluster (single-node VM) for monitoring infrastructure (Prometheus, Grafana, VictoriaMetrics, Coroot, etc.). The monitoring cluster is isolated from production on a separate Proxmox host and network. All services are accessed via Traefik LoadBalancer ingress (10.30.0.90) with DNS-based routing.

### Service Access

| Service | Internal URL | External URL | Purpose |
|---------|-------------|-------------|---------|
| Grafana | https://grafana.kernow.io | https://grafana.kernow.io | Dashboards |
| Coroot | https://coroot.kernow.io | https://coroot.kernow.io | eBPF Observability |
| Beszel | https://beszel.kernow.io | https://beszel.kernow.io | Host Monitoring |
| Prometheus | http://prometheus.monit.kernow.io | - | Metrics |
| AlertManager | http://alertmanager.monit.kernow.io | - | Alerts |
| VictoriaMetrics | http://victoriametrics.monit.kernow.io | - | TSDB |
| VictoriaLogs | http://victorialogs.monit.kernow.io | - | Logs |
| Gatus | http://gatus.monit.kernow.io | - | Health Checks |
| Traefik | http://traefik.monit.kernow.io | - | Dashboard |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Deployment Pipeline                                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. Terraform   → Create Talos VM on Proxmox Carrick            │
│ 2. Terraform   → Bootstrap Talos + Kubernetes + Cilium CNI     │
│ 3. ArgoCD      → Deploy monitoring stack (GitOps from prod)    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Proxmox Carrick (10.30.0.10)                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Talos Monitor VM (VMID: 200, IP: 10.30.0.20)               │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ Talos Linux v1.11.5 (immutable OS)                     │ │ │
│ │ │ Kubernetes v1.34.1                                      │ │ │
│ │ │ Cilium CNI (LB pool: 10.30.0.90-99)                   │ │ │
│ │ │                                                         │ │ │
│ │ │ ┌─────────────────────────────────────────────────────┐ │ │ │
│ │ │ │ Monitoring Stack                                     │ │ │ │
│ │ │ │ - Prometheus, Grafana, VictoriaMetrics, etc.        │ │ │ │
│ │ │ │ - Managed by ArgoCD (GitOps from prod cluster)      │ │ │ │
│ │ │ └─────────────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ Network: vmbr0 (10.30.0.0/24)                                   │
│ Storage: Kerrier ZFS pool                                       │
└─────────────────────────────────────────────────────────────────┘

Management: iac LXC (10.10.0.175) - Runs Terraform, talosctl
Production: Proxmox Ruapehu (10.10.0.10) - Separate cluster
```

### Key Features

- **Talos Linux**: Immutable, API-driven OS (same as prod and agentic clusters)
- **Cilium CNI**: Networking and LoadBalancer via L2 announcements
- **Network Isolation**: Monitoring on 10.30.0.0/24, Production on 10.10.0.0/24
- **GitOps**: ArgoCD (on prod cluster) manages monitoring stack deployment
- **Terraform-managed**: Full VM lifecycle via Terraform

## Prerequisites

### Required Tools
- **Terraform** >= 1.10 (installed on iac LXC)
- **talosctl** (installed on iac LXC)
- **kubectl** >= 1.34 (installed on iac LXC)

### Access Requirements
- Proxmox Carrick API credentials
- Network access to 10.30.0.0/24

## Quick Start

### 1. Deploy Infrastructure (Terraform)

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=monitoring.plan

# Apply (creates Talos VM, bootstraps Kubernetes, installs Cilium)
terraform apply monitoring.plan
```

### 2. Verify Cluster

```bash
# Set kubeconfig
export KUBECONFIG=/home/monit_homelab/kubeconfig

# Check cluster
kubectl get nodes -o wide
# Expected: 1 node (talos-monitor) in Ready state, Talos Linux OS

kubectl get pods -A
# Expected: kube-system pods + cilium pods running

kubectl cluster-info
# Expected: Kubernetes control plane at https://10.30.0.20:6443
```

### 3. Verify with talosctl

```bash
# Check Talos health
talosctl --nodes 10.30.0.20 health

# View Talos dashboard
talosctl --nodes 10.30.0.20 dashboard
```

## Repository Structure

```
/home/monit_homelab/
├── terraform/
│   └── talos-single-node/          # Active: Talos VM + K8s bootstrap
│       ├── main.tf                 # VM definition + Talos bootstrap
│       ├── variables.tf            # Cluster configuration
│       ├── providers.tf            # Proxmox + Talos providers
│       ├── cilium.tf               # Cilium CNI + LB pool
│       ├── storage.tf              # NFS PV definitions
│       ├── infisical.tf            # Secret management
│       ├── locals.tf / data.tf     # Helpers
│       ├── outputs.tf              # Cluster info outputs
│       └── versions.tf             # Provider versions
│
├── kubernetes/
│   ├── bootstrap/                  # App-of-apps root Application
│   ├── argocd-apps/                # ArgoCD Application definitions
│   └── platform/                   # Workload manifests
│       ├── monitoring-namespace.yaml
│       ├── storage/                # NFS PV/PVC definitions
│       ├── beszel/                 # Host monitoring
│       └── gatus/                  # Endpoint health checks
│
├── scripts/
│   ├── generate-talos-image.sh     # Custom Talos factory image builder
│   └── sync-coroot-api-keys.sh     # Coroot API key sync
│
├── docs/                           # Additional documentation
├── kubeconfig                      # Cluster kubeconfig
├── renovate.json                   # Dependency update config
├── CLAUDE.md                       # Claude Code context
├── README.md                       # This file
├── GITOPS-WORKFLOW.md              # GitOps rules
└── renovate.json                   # Dependency update config
```

## Deployment Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Terraform (Infrastructure)                               │
│    cd terraform/talos-single-node                           │
│    terraform init && terraform apply                        │
│    → Creates Talos VM, bootstraps K8s, installs Cilium     │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Verification                                              │
│    kubectl get nodes (talos-monitor Ready)                  │
│    talosctl health (Talos healthy)                          │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. ArgoCD Deployment (from prod cluster)                    │
│    ArgoCD manages monitoring stack via GitOps               │
│    Push kubernetes/ changes → ArgoCD auto-syncs             │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Details

### Terraform Variables

See `terraform/talos-single-node/variables.tf` for full list. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `talos_version` | v1.11.5 | Talos Linux version |
| `kubernetes_version` | v1.34.1 | Kubernetes version |
| `cluster_name` | monitoring-cluster | Cluster name |
| `monitoring_node.vmid` | 200 | VM ID on Proxmox |
| `monitoring_node.name` | talos-monitor | VM hostname |
| `monitoring_node.ip` | 10.30.0.20 | Node IP address |
| `monitoring_node.cores` | 4 | CPU cores |
| `monitoring_node.memory` | 12288 | RAM in MB (12GB) |
| `monitoring_node.disk` | 50 | Disk size in GB |
| `cilium_lb_ip_pool` | 10.30.0.90-99 | Cilium LB IP range |

## Troubleshooting

### Talos Node Issues

```bash
# Check Talos node health
talosctl --nodes 10.30.0.20 health

# View Talos logs
talosctl --nodes 10.30.0.20 logs kubelet
talosctl --nodes 10.30.0.20 logs containerd

# View Talos dashboard (interactive)
talosctl --nodes 10.30.0.20 dashboard

# Check Talos services
talosctl --nodes 10.30.0.20 services

# Reboot node (if needed)
talosctl --nodes 10.30.0.20 reboot
```

### Kubernetes Issues

```bash
# Set kubeconfig
export KUBECONFIG=/home/monit_homelab/kubeconfig

# Check node status
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check events
kubectl get events -A --sort-by=.lastTimestamp

# Check Cilium status
kubectl -n kube-system exec ds/cilium -- cilium status
```

### Kubeconfig Issues

```bash
# Verify kubeconfig exists
ls -la /home/monit_homelab/kubeconfig

# Verify server address
grep server /home/monit_homelab/kubeconfig

# Test connection
kubectl --kubeconfig /home/monit_homelab/kubeconfig get nodes

# Regenerate kubeconfig via Terraform
cd /home/monit_homelab/terraform/talos-single-node
terraform output -raw kubeconfig > /home/monit_homelab/kubeconfig
```

### NFS Storage Issues

```bash
# Check PV status
kubectl get pv
kubectl describe pv victoria-metrics-pv

# Check PVC bindings
kubectl get pvc -n monitoring

# Verify NFS server is reachable
kubectl run nfs-test --rm -it --image=busybox -- ping -c3 10.30.0.120
```

## Maintenance

### Updating Talos

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Update talos_version in variables.tf, then:
terraform plan -out=upgrade.plan
terraform apply upgrade.plan

# Or use talosctl for in-place upgrade:
talosctl --nodes 10.30.0.20 upgrade --image=factory.talos.dev/installer/<schematic>:v1.x.x
```

### Destroying Infrastructure

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Plan destruction
terraform plan -destroy

# Destroy VM
terraform destroy
```

## Network Configuration

### IP Allocation

| Resource | IP | Network | Purpose |
|----------|----|---------| --------|
| Carrick Proxmox | 10.30.0.10 | 10.30.0.0/24 | Hypervisor |
| Gateway | 10.30.0.1 | 10.30.0.0/24 | Network gateway |
| Talos Monitor | 10.30.0.20 | 10.30.0.0/24 | Monitoring cluster |
| Traefik LB | 10.30.0.90 | 10.30.0.0/24 | Cilium LoadBalancer |
| TrueNAS-M | 10.30.0.120 | 10.30.0.0/24 | NFS storage |
| iac LXC | 10.10.0.175 | 10.10.0.0/24 | Management/Terraform |

### Network Isolation

- **Monitoring Network**: 10.30.0.0/24 (Carrick)
- **Production Network**: 10.10.0.0/24 (Ruapehu)
- **Routing**: iac LXC can reach both networks for management

## Architecture Decisions

### Why Talos Linux?

- **Consistency**: Same OS as prod and agentic clusters
- **Immutable**: No drift, no manual changes possible
- **API-driven**: All operations via talosctl or Terraform
- **Secure**: Minimal attack surface, no SSH, no shell

### Why Single-Node?

- **Monitoring workload**: Doesn't need HA for the monitoring stack itself
- **Resource efficiency**: One VM with 4 cores + 12GB RAM is sufficient
- **Simplicity**: Fewer moving parts for the monitoring cluster

### Why Cilium?

- **LoadBalancer**: L2 announcements for service exposure (10.30.0.90-99)
- **Consistency**: Same CNI as other clusters
- **Observability**: Built-in Hubble for network visibility

## Migration History

This cluster was originally deployed as K3s on a Debian 13 LXC container (Dec 2025). It was migrated to Talos Linux on a Proxmox VM (Dec 2025) for consistency with prod and agentic clusters. Legacy K3s-era artifacts were removed in Jan 2026; they remain in git history if needed.

## References

- **Talos Documentation**: https://www.talos.dev/
- **Cilium Documentation**: https://docs.cilium.io/
- **Proxmox Provider**: https://registry.terraform.io/providers/bpg/proxmox
- **Production Homelab**: /home/prod_homelab
- **Agentic Homelab**: /home/agentic_lab
