# Monitoring Homelab - Talos Linux on Proxmox Pihanga

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

This repository deploys a Talos Linux Kubernetes cluster (single-node VM) for monitoring infrastructure (Prometheus, Grafana, VictoriaMetrics, Coroot, etc.). The monitoring cluster runs on Proxmox Pihanga on the production network. All services are accessed via Traefik LoadBalancer ingress with DNS-based routing.

### Service Access

| Service | Internal URL | External URL | Purpose |
|---------|-------------|-------------|---------|
| Grafana | https://grafana.kernow.io | https://grafana.kernow.io | Dashboards |
| Coroot | https://coroot.kernow.io | https://coroot.kernow.io | eBPF Observability |
| Beszel | https://beszel.kernow.io | https://beszel.kernow.io | Host Monitoring |
| Pulse | https://pulse.kernow.io | https://pulse.kernow.io | Server Monitoring |
| Tugtainer | https://tugtainer.kernow.io | https://tugtainer.kernow.io | Container Updates |
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
│ 1. Terraform   → Create Talos VM on Proxmox Pihanga            │
│ 2. Terraform   → Bootstrap Talos + Kubernetes + Cilium CNI     │
│ 3. ArgoCD      → Deploy monitoring stack (GitOps from prod)    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Proxmox Pihanga (10.10.0.20)                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Talos Monitor VM (VMID: 200, IP: 10.10.0.30)               │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ Talos Linux v1.11.5 (immutable OS)                     │ │ │
│ │ │ Kubernetes v1.34.1                                      │ │ │
│ │ │ Cilium CNI (LB pool: 10.10.0.31-35)                   │ │ │
│ │ │                                                         │ │ │
│ │ │ ┌─────────────────────────────────────────────────────┐ │ │ │
│ │ │ │ Monitoring Stack                                     │ │ │ │
│ │ │ │ - Prometheus, Grafana, VictoriaMetrics, etc.        │ │ │ │
│ │ │ │ - Managed by ArgoCD (GitOps from prod cluster)      │ │ │ │
│ │ │ └─────────────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ Network: vmbr0 (10.10.0.0/24, Production)                       │
│ Storage: Local SSD (boot) + NFS from TrueNAS-HDD (data)        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

- **Talos Linux**: Immutable, API-driven OS (same as prod and agentic clusters)
- **Cilium CNI**: Networking and LoadBalancer via L2 announcements
- **GitOps**: ArgoCD (on prod cluster) manages monitoring stack deployment
- **Terraform-managed**: Full VM lifecycle via Terraform

## Prerequisites

### Required Tools
- **Terraform** >= 1.10
- **talosctl**
- **kubectl** >= 1.34

### Access Requirements
- Proxmox Pihanga API credentials
- Network access to 10.10.0.0/24

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
# Expected: Kubernetes control plane at https://10.10.0.30:6443
```

### 3. Verify with talosctl

```bash
# Check Talos health
talosctl --nodes 10.10.0.30 health

# View Talos dashboard
talosctl --nodes 10.10.0.30 dashboard
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
│       ├── tugtainer/              # Container update management
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
└── GITOPS-WORKFLOW.md              # GitOps rules
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
| `monitoring_node.ip` | 10.10.0.30 | Node IP address |
| `monitoring_node.cores` | 4 | CPU cores |
| `monitoring_node.memory` | 12288 | RAM in MB (12GB) |
| `monitoring_node.disk` | 50 | Disk size in GB |
| `cilium_lb_ip_pool` | 10.10.0.31-35 | Cilium LB IP range |

## Troubleshooting

### Talos Node Issues

```bash
# Check Talos node health
talosctl --nodes 10.10.0.30 health

# View Talos logs
talosctl --nodes 10.10.0.30 logs kubelet
talosctl --nodes 10.10.0.30 logs containerd

# View Talos dashboard (interactive)
talosctl --nodes 10.10.0.30 dashboard

# Check Talos services
talosctl --nodes 10.10.0.30 services

# Reboot node (if needed)
talosctl --nodes 10.10.0.30 reboot
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
kubectl run nfs-test --rm -it --image=busybox -- ping -c3 10.20.0.103
```

## Network Configuration

### IP Allocation

| Resource | IP | Purpose |
|----------|--------|---------|
| Pihanga (Proxmox) | 10.10.0.20 | Hypervisor |
| Gateway | 10.10.0.1 | Network gateway (OPNsense) |
| Talos Monitor | 10.10.0.30 | Monitoring cluster node |
| Cilium LB Pool | 10.10.0.31-35 | LoadBalancer IPs |
| TrueNAS-HDD | 10.20.0.103 | NFS storage |

## Maintenance

### Updating Talos

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Update talos_version in variables.tf, then:
terraform plan -out=upgrade.plan
terraform apply upgrade.plan

# Or use talosctl for in-place upgrade:
talosctl --nodes 10.10.0.30 upgrade --image=factory.talos.dev/installer/<schematic>:v1.x.x
```

### Destroying Infrastructure

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Plan destruction
terraform plan -destroy

# Destroy VM
terraform destroy
```

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

- **LoadBalancer**: L2 announcements for service exposure (10.10.0.31-35)
- **Consistency**: Same CNI as other clusters
- **Observability**: Built-in Hubble for network visibility

## Migration History

This cluster was originally deployed as K3s on a Debian 13 LXC container on Proxmox Carrick (10.30.0.0/24 network) in Dec 2025. It was migrated to Talos Linux on a Proxmox VM, then relocated to Pihanga (10.10.0.0/24) for consistency with the production network. Legacy K3s-era artifacts were removed in Jan 2026; they remain in git history if needed.

## References

- **Talos Documentation**: https://www.talos.dev/
- **Cilium Documentation**: https://docs.cilium.io/
- **Proxmox Provider**: https://registry.terraform.io/providers/bpg/proxmox
- **Production Homelab**: /home/prod_homelab
- **Agentic Homelab**: /home/agentic_lab
