# Monitoring Homelab - Talos Linux Cluster

## Cluster Overview

| Property | Value |
|----------|-------|
| **OS** | Talos Linux v1.11.5 |
| **Kubernetes** | v1.34.1 |
| **Type** | Single-node control-plane VM |
| **Hostname** | talos-monitor |
| **VMID** | 200 |
| **IP** | 10.30.0.20 |
| **Network** | 10.30.0.0/24 (Monitoring) |
| **Proxmox Host** | Carrick (10.30.0.10) |
| **CNI** | Cilium |
| **LB IP Pool** | 10.30.0.90-99 (Cilium) |
| **Storage** | Kerrier ZFS pool (boot) + NFS from TrueNAS (data) |

**IMPORTANT**: This is a Talos Linux VM, NOT K3s, NOT an LXC container. Talos is immutable - there is no SSH access, no apt-get, no systemd. Use `talosctl` for node operations.

## Kubeconfig & Talosctl

```bash
# Kubeconfig
export KUBECONFIG=/home/monit_homelab/kubeconfig

# Talosctl (no talosconfig generated in this repo - use terraform output)
talosctl --nodes 10.30.0.20 --talosconfig <path> health
```

## Infrastructure (Terraform)

Active Terraform configuration:
```
terraform/talos-single-node/    # ACTIVE - Talos VM on Proxmox Carrick
├── main.tf                     # VM + Talos bootstrap
├── variables.tf                # Cluster config (versions, resources)
├── providers.tf                # Proxmox + Talos providers
├── cilium.tf                   # Cilium CNI + LB pool
├── storage.tf                  # NFS PVs for monitoring data
├── infisical.tf                # Secret management
├── locals.tf / data.tf         # Helper definitions
├── outputs.tf / versions.tf    # Outputs + version constraints
└── .terraform/                 # Provider cache
```

Legacy K3s-era directories (`ansible/`, `semaphore/`, `terraform/lxc-only/`) were deleted in Jan 2026. They remain in git history. The `terraform/monitoring-lxc.backup-20251215/` directory exists on disk (gitignored) as an archived backup.

## Repository Structure

```
/home/monit_homelab/
├── terraform/talos-single-node/  # Active Terraform (Talos VM)
├── kubernetes/                   # K8s manifests (ArgoCD-managed)
│   ├── bootstrap/                # App-of-apps root
│   ├── argocd-apps/              # ArgoCD Application definitions
│   └── platform/                 # Workload manifests
├── scripts/
│   ├── generate-talos-image.sh   # Custom Talos factory image builder
│   └── sync-coroot-api-keys.sh   # Coroot API key sync
├── docs/                         # Additional documentation
├── kubeconfig                    # Cluster kubeconfig
├── renovate.json                 # Dependency updates
└── renovate.json                 # Dependency updates
```

## Services

| Service | Internal URL | External URL |
|---------|-------------|-------------|
| Grafana | https://grafana.kernow.io | https://grafana.kernow.io |
| Coroot | https://coroot.kernow.io | https://coroot.kernow.io |
| Beszel | https://beszel.kernow.io | https://beszel.kernow.io |
| Prometheus | http://prometheus.monit.kernow.io | - |
| AlertManager | http://alertmanager.monit.kernow.io | - |
| VictoriaMetrics | http://victoriametrics.monit.kernow.io | - |
| VictoriaLogs | http://victorialogs.monit.kernow.io | - |
| Gatus | http://gatus.monit.kernow.io | - |
| Traefik | http://traefik.monit.kernow.io | - |

## Network

| Resource | IP | Purpose |
|----------|-----|---------|
| Carrick (Proxmox) | 10.30.0.10 | Hypervisor (proxmox-monit.kernow.io) |
| Gateway | 10.30.0.1 | Network gateway |
| talos-monitor | 10.30.0.20 | Monitoring cluster node |
| Traefik LB | 10.30.0.90 | Ingress load balancer (Cilium) |
| TrueNAS-M | 10.30.0.120 | NFS storage |

## Storage

NFS from TrueNAS (10.30.0.120):
- `/mnt/Restormal/victoria-metrics` (200GB) - VictoriaMetrics TSDB
- `/mnt/Trelawney/victoria-logs` (500GB) - VictoriaLogs

## GitOps Workflow

All changes via Git + ArgoCD (managed from prod cluster):
1. Edit manifests in `kubernetes/`
2. Commit and push to GitHub
3. ArgoCD on prod cluster syncs to monitoring cluster

Terraform changes:
1. Edit `.tf` files in `terraform/talos-single-node/`
2. Commit and push
3. Run `terraform plan` then `terraform apply`

## Key Differences from Prod/Agentic

- **Single-node**: One control-plane VM (no workers)
- **No local ArgoCD**: Managed remotely by prod cluster's ArgoCD
- **Talos (like prod/agentic)**: Same OS, same tooling, same patterns
- **Cilium CNI**: LoadBalancer via Cilium L2 announcements
- **Monitoring-only**: No application workloads

## Common Mistakes to Avoid

- Do NOT refer to this as K3s - it was migrated to Talos
- Do NOT SSH to 10.30.0.20 - Talos has no SSH
- Do NOT use `apt-get`, `systemctl`, or other Linux admin commands - Talos is immutable
- Do NOT reference `/etc/rancher/k3s/` paths - K3s is not installed
- Do NOT use `ansible/` or `terraform/lxc-only/` - these are legacy from the K3s era
- Do NOT reference VMID 200 as an LXC - it is a VM
