# Talos Monitoring Cluster - Deployment Summary

## Overview

Talos Linux monitoring cluster deployed on Proxmox Pihanga via Terraform. Single-node control-plane VM running the full monitoring stack.

## Cluster Specifications

| Component | Specification |
|-----------|--------------|
| **Platform** | Talos Linux v1.11.5 (Proxmox VM) |
| **Kubernetes** | v1.34.1 |
| **CNI** | Cilium (L2 announcements) |
| **VMID** | 200 |
| **Hostname** | talos-monitor |
| **IP Address** | 10.10.0.30 |
| **CPU Cores** | 4 |
| **Memory** | 12GB (12288MB) |
| **Boot Disk** | 50GB (local SSD) |
| **Network** | vmbr0 (10.10.0.0/24, Production) |
| **LB IP Pool** | 10.10.0.31-35 (Cilium) |

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Production Network (10.10.0.0/24)                               │
│                                                                   │
│ Proxmox Ruapehu: 10.10.0.10 — Prod cluster (multi-node)        │
│ Proxmox Pihanga: 10.10.0.20 — Monit cluster (single-node)      │
│                                                                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Talos Monitor VM (VMID: 200)                                │ │
│ │ IP: 10.10.0.30                                              │ │
│ │ Talos Linux v1.11.5 + K8s v1.34.1 + Cilium                │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Terraform Configuration

Active: `terraform/talos-single-node/`

```
terraform/talos-single-node/
├── main.tf          # Proxmox VM + Talos machine config + bootstrap
├── variables.tf     # All cluster configuration
├── providers.tf     # Proxmox + Talos providers
├── cilium.tf        # Cilium CNI + LoadBalancer IP pool
├── storage.tf       # NFS PV definitions
├── infisical.tf     # Secret management integration
├── locals.tf        # Local values
├── data.tf          # Data sources
├── outputs.tf       # Cluster outputs (kubeconfig, etc.)
└── versions.tf      # Provider version constraints
```

## Deployment

```bash
cd /home/monit_homelab/terraform/talos-single-node
terraform init
terraform plan -out=monitoring.plan
terraform apply monitoring.plan
```

## Verification

```bash
export KUBECONFIG=/home/monit_homelab/kubeconfig

# Kubernetes
kubectl get nodes -o wide
# NAME            STATUS   ROLES           VERSION   OS-IMAGE
# talos-monitor   Ready    control-plane   v1.34.1   Talos (v1.11.5)

# Talos
talosctl --nodes 10.10.0.30 health
```

## Comparison with Other Clusters

| Aspect | Production (Ruapehu) | Monitoring (Pihanga) | Agentic (Hikurangi) |
|--------|---------------------|----------------------|--------------------|
| **Proxmox IP** | 10.10.0.10 | 10.10.0.20 | 10.30.0.10 |
| **Network** | 10.10.0.0/24 | 10.10.0.0/24 | 10.20.0.0/24 |
| **OS** | Talos Linux | Talos Linux | Talos Linux |
| **Nodes** | 1 CP + 3 workers | 1 CP (single-node) | 1 CP + workers |
| **CNI** | Cilium | Cilium | Cilium |
| **Storage** | Ranginui/Taranaki ZFS | Local SSD + NFS | ZFS |
| **ArgoCD** | Local (self-managed) | Remote (from prod) | No ArgoCD |
| **Purpose** | Production workloads | Monitoring infrastructure | AI platform |

## Migration History

- **Dec 2025**: Originally deployed as K3s on Debian 13 LXC (VMID 200) on Proxmox Carrick (10.30.0.0/24)
- **Dec 2025**: Migrated to Talos Linux VM for consistency across all clusters
- **Jan 2026**: Relocated to Proxmox Pihanga (10.10.0.0/24)
- Legacy K3s artifacts removed Jan 2026 (available in git history)

---

**Status**: Deployed and operational
**Last updated**: 2026-02
