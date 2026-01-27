# Monitoring Stack Deployment - Roadmap

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Proxmox Carrick (10.30.0.10)                                                │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ TrueNAS-M (10.30.0.120 - Same network as Talos node)                   │ │
│ │ ┌──────────────────────────────────────────────────────────────────────┐│ │
│ │ │ NFS Exports:                                                         ││ │
│ │ │ - Restormal (200GB) → VictoriaMetrics storage                       ││ │
│ │ │ - Trelawney (500GB) → VictoriaLogs storage                          ││ │
│ │ └──────────────────────────────────────────────────────────────────────┘│ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                               │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ Talos Monitor VM (VMID: 200, IP: 10.30.0.20)                           │ │
│ │ Talos Linux v1.11.5 + Kubernetes v1.34.1 + Cilium CNI                  │ │
│ │ ┌──────────────────────────────────────────────────────────────────────┐│ │
│ │ │ Monitoring Stack (managed by ArgoCD from prod cluster)               ││ │
│ │ │ ├─ Prometheus (scraping prod + monitoring)                          ││ │
│ │ │ ├─ VictoriaMetrics (200GB NFS ← Restormal)                          ││ │
│ │ │ ├─ VictoriaLogs (500GB NFS ← Trelawney)                             ││ │
│ │ │ ├─ Grafana (dashboards)                                             ││ │
│ │ │ ├─ AlertManager (Slack/Discord alerts)                              ││ │
│ │ │ ├─ Coroot (eBPF observability)                                      ││ │
│ │ │ ├─ Beszel (host monitoring)                                         ││ │
│ │ │ └─ Gatus (endpoint status)                                          ││ │
│ │ └──────────────────────────────────────────────────────────────────────┘│ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                   ↕ Monitors
┌─────────────────────────────────────────────────────────────────────────────┐
│ Production Network (10.10.0.0/24) - Proxmox Ruapehu                        │
│ ├─ Talos K8s Cluster (CP + 3 workers)                                      │
│ ├─ Plex VM (GPU transcode)                                                 │
│ ├─ OPNsense Router                                                          │
│ └─ AdGuard DNS                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Phase Breakdown

### Phase 1: Infrastructure (COMPLETED)

**What:** Provision Talos Linux VM on Proxmox Carrick

**Deliverables:**
- Terraform configuration for Talos VM provisioning (`terraform/talos-single-node/`)
- Automated Talos bootstrap + Kubernetes + Cilium CNI
- Kubeconfig exported to `/home/monit_homelab/kubeconfig`
- Network isolation (10.30.0.0/24 vs prod 10.10.0.0/24)
- Cilium LoadBalancer IP pool (10.30.0.90-99)

**Deployment:**
```bash
cd /home/monit_homelab/terraform/talos-single-node
terraform init
terraform plan -out=monitoring.plan
terraform apply monitoring.plan
```

**Validation:**
```bash
export KUBECONFIG=/home/monit_homelab/kubeconfig
kubectl get nodes -o wide
# talos-monitor   Ready   control-plane   v1.34.1   Talos (v1.11.5)

talosctl --nodes 10.30.0.20 health
```

---

### Phase 2: Monitoring Stack (COMPLETED)

**What:** Deploy monitoring applications to Talos cluster via ArgoCD

**Applications Deployed:**

| App | Purpose | Storage | Network |
|-----|---------|---------|---------|
| **Prometheus** | Metrics scraping | Internal (small) | Scrapes 10.10.0.0/24 + 10.30.0.0/24 |
| **VictoriaMetrics** | Long-term metrics storage | 200GB NFS (Restormal) | Internal query |
| **VictoriaLogs** | Log aggregation | 500GB NFS (Trelawney) | Internal query |
| **Grafana** | Visualization dashboards | 1GB local | HTTPS via Traefik + Cloudflare |
| **AlertManager** | Alert routing | 1GB local | Slack/Discord webhooks |
| **Coroot** | eBPF observability | Local | HTTPS via Traefik + Cloudflare |
| **Beszel** | Host/container monitoring | 1GB local | HTTPS via Traefik + Cloudflare |
| **Gatus** | Endpoint status checks | 100MB local | HTTP checks to all services |

---

### Phase 3: Integration & Monitoring Targets (ONGOING)

**What:** Connect monitoring to production infrastructure

**Scrape Targets:**

| Target | Type | IP | Port | Metrics |
|--------|------|----|----|---------|
| Proxmox Ruapehu | Proxmox VE API | 10.10.0.10 | 8006 | VM/LXC metrics, CPU, RAM, storage |
| Proxmox Carrick | Proxmox VE API | 10.30.0.10 | 8006 | VM/LXC metrics, CPU, RAM, storage |
| Talos Control Plane | Kubernetes API | 10.10.0.40 | 6443 | K8s metrics, pods, nodes |
| Talos Workers (x3) | Kubernetes API | 10.10.0.41-43 | 6443 | K8s metrics, pods, nodes |
| Plex VM | Node Exporter | 10.10.0.50 | 9100 | Host metrics, GPU usage |
| OPNsense | OPNsense Exporter | 10.10.0.1 | 9273 | Firewall, traffic, VPN |
| AdGuard | AdGuard Exporter | 10.10.0.1 | 9617 | DNS queries, blocking |
| TrueNAS (Carrick) | TrueNAS API | 10.30.0.120 | 443 | Storage, NFS stats |

---

### Phase 4: External Monitoring (OPTIONAL)

**What:** Deploy external VPS for outside-in monitoring

**Setup:**
- VPS for external Gatus instance
- Monitors production from outside the network
- Detects ISP/network failures
- Alerts when prod cluster is unreachable from internet

---

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Production Network (vmbr0): 10.10.0.0/24                        │
│ ├─ Proxmox Ruapehu: 10.10.0.10                                 │
│ ├─ Talos Control Plane: 10.10.0.40                             │
│ ├─ Talos Workers: 10.10.0.41-43                                │
│ ├─ Plex VM: 10.10.0.50                                         │
│ └─ OPNsense/AdGuard: 10.10.0.1                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↕ Routed
┌─────────────────────────────────────────────────────────────────┐
│ Monitoring Network (vmbr0): 10.30.0.0/24                       │
│ ├─ Proxmox Carrick: 10.30.0.10                                 │
│ ├─ Talos Monitor: 10.30.0.20                                   │
│ ├─ Traefik LB: 10.30.0.90 (Cilium)                            │
│ └─ TrueNAS-M: 10.30.0.120                                      │
│    └─ NFS Exports: Restormal (200GB), Trelawney (500GB)        │
└─────────────────────────────────────────────────────────────────┘
```

**Network Routing:**
- Talos Monitor (10.30.0.20) can scrape Production (10.10.0.0/24) via routing
- Talos Monitor can mount NFS from TrueNAS (10.30.0.120) - same network
- Production cluster cannot reach monitoring (one-way monitoring)

---

## Storage Strategy

### VictoriaMetrics (200GB on Restormal)
- Prometheus-compatible time-series database
- 200GB for ~1 year retention at 1-minute scrape interval
- NFS mount: `10.30.0.120:/mnt/Restormal/victoria-metrics`

### VictoriaLogs (500GB on Trelawney)
- Log aggregation and search
- 500GB for ~6 months retention
- NFS mount: `10.30.0.120:/mnt/Trelawney/victoria-logs`

---

## Security Considerations

### Secrets Management (Infisical)

All sensitive values stored in Infisical:

| Secret | Purpose |
|--------|---------|
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin login |
| `ALERTMANAGER_SLACK_WEBHOOK` | Slack alert notifications |
| `ALERTMANAGER_DISCORD_WEBHOOK` | Discord alert notifications |
| `BESZEL_API_KEY` | Beszel agent authentication |
| `GATUS_API_KEY` | Gatus API access |
| `CLOUDFLARE_TUNNEL_TOKEN` | Cloudflare Tunnel for external access |

### Network Isolation

- Monitoring on separate subnet (10.30.0.0/24)
- One-way traffic (monitoring scrapes production, not reverse)
- Firewall rules limit ingress to monitoring VM

### Talos Security

- Immutable OS - no shell access, no SSH
- API-driven only (talosctl)
- Minimal attack surface

---

## Success Criteria

### Phase 1 (Infrastructure)
- [x] Talos VM running on Proxmox Carrick
- [x] Kubeconfig works: `kubectl get nodes`
- [x] Talos healthy: `talosctl health`
- [x] Terraform configuration valid and documented
- [x] Git repository initialized and committed

### Phase 2 (Monitoring Stack)
- [x] All monitoring pods running
- [x] VictoriaMetrics has 200GB PV mounted from Restormal
- [x] VictoriaLogs has 500GB PV mounted from Trelawney
- [x] Grafana accessible with VictoriaMetrics datasource
- [x] Prometheus scraping targets
- [x] Coroot, Beszel, Gatus deployed

### Phase 3 (Integration)
- [ ] All production hosts reporting metrics
- [ ] Grafana dashboards for Proxmox, Talos, Plex, OPNsense
- [ ] Alerts firing correctly to Slack/Discord

---

## References

- **README**: `/home/monit_homelab/README.md`
- **Deployment Summary**: `/home/monit_homelab/DEPLOYMENT_SUMMARY.md`
- **GitOps Workflow**: `/home/monit_homelab/GITOPS-WORKFLOW.md`
- **Production Reference**: `/home/prod_homelab/`
