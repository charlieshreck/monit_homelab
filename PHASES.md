# Monitoring Stack Deployment - Complete Roadmap

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Proxmox Carrick (10.30.0.10)                                                │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ TrueNAS VM/LXC (Network: 10.40.0.0/24)                                  │ │
│ │ ┌──────────────────────────────────────────────────────────────────────┐│ │
│ │ │ NVMe-oF Exports:                                                     ││ │
│ │ │ - Restormal (200GB) → VictoriaMetrics storage                       ││ │
│ │ │ - Trelawney (500GB) → VictoriaLogs storage                          ││ │
│ │ └──────────────────────────────────────────────────────────────────────┘│ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                               │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ K3s Monitor LXC (VMID: 200, IP: 10.30.0.20/24) ← PHASE 1 (DONE)        │ │
│ │ ┌──────────────────────────────────────────────────────────────────────┐│ │
│ │ │ K3s Cluster + Monitoring Stack ← PHASE 2 (NEXT)                     ││ │
│ │ │ ├─ Prometheus (scraping prod + monitoring)                          ││ │
│ │ │ ├─ VictoriaMetrics (200GB NFS ← Restormal)                          ││ │
│ │ │ ├─ VictoriaLogs (500GB NFS ← Trelawney)                             ││ │
│ │ │ ├─ Grafana (dashboards)                                             ││ │
│ │ │ ├─ AlertManager (Slack/Discord alerts)                              ││ │
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

### ✅ Phase 1: Infrastructure (COMPLETED)

**What:** Provision K3s LXC on Proxmox Carrick

**Deliverables:**
- Terraform configuration for LXC provisioning
- Automated K3s installation
- Kubeconfig extraction to `~/.kube/monitoring-k3s.yaml`
- Network isolation (10.30.0.0/24 vs prod 10.10.0.0/24)
- SSH key provisioning for secure access

**Files Created:**
```
/home/monit_homelab/
├── terraform/monitoring-lxc/
│   ├── providers.tf           # Dual Proxmox provider setup
│   ├── versions.tf             # Provider versions
│   ├── variables.tf            # All configuration variables
│   ├── main.tf                 # LXC + K3s deployment
│   ├── outputs.tf              # Cluster information
│   └── terraform.tfvars.example # Configuration template
├── README.md                   # Complete setup guide
├── ENVIRONMENT_VARIABLES.md    # Credential configuration
├── DEPLOYMENT_SUMMARY.md       # Architecture summary
└── .gitignore                  # Security controls
```

**Deployment:**
```bash
cd /home/monit_homelab/terraform/monitoring-lxc
source ~/.config/terraform/monitoring-creds.env
terraform init
terraform plan -out=monitoring.plan
terraform apply monitoring.plan
```

**Validation:**
```bash
# Test K3s cluster
export KUBECONFIG=~/.kube/monitoring-k3s.yaml
kubectl get nodes
kubectl get pods -A

# SSH to container
ssh root@10.30.0.20
```

---

### 🔄 Phase 2: Monitoring Stack (NEXT)

**What:** Deploy monitoring applications to K3s cluster

**Prerequisites:**
1. Phase 1 complete (K3s cluster running)
2. TrueNAS VM/LXC on Carrick with NVMe-oF exports
3. Infisical `/monitoring` folder with secrets
4. GitHub Personal Access Token (for ArgoCD)
5. Monitoring cluster registered with prod ArgoCD

**Applications to Deploy:**

| App | Purpose | Storage | Network |
|-----|---------|---------|---------|
| **Prometheus** | Metrics scraping | Internal (small) | Scrapes 10.10.0.0/24 + 10.30.0.0/24 |
| **VictoriaMetrics** | Long-term metrics storage | 200GB NFS (Restormal) | Internal query |
| **VictoriaLogs** | Log aggregation | 500GB NFS (Trelawney) | Internal query |
| **Grafana** | Visualization dashboards | 1GB local | HTTP 3000, Cloudflare Tunnel |
| **AlertManager** | Alert routing | 1GB local | Slack/Discord webhooks |
| **Beszel** | Host/container monitoring | 1GB local | SSH to monitored hosts |
| **Gatus** | Endpoint status checks | 100MB local | HTTP checks to all services |

**Storage Configuration:**

```yaml
# VictoriaMetrics PV (from TrueNAS Restormal via NVMe-oF)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoria-metrics-pv
spec:
  capacity:
    storage: 200Gi
  accessModes: [ReadWriteOnce]
  nfs:
    server: 10.40.0.10  # TrueNAS on Carrick
    path: /mnt/Restormal/victoria-metrics

# VictoriaLogs PV (from TrueNAS Trelawney via NVMe-oF)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoria-logs-pv
spec:
  capacity:
    storage: 500Gi
  accessModes: [ReadWriteOnce]
  nfs:
    server: 10.40.0.10  # TrueNAS on Carrick
    path: /mnt/Trelawney/victoria-logs
```

**Files to Create:**
```
/home/monit_homelab/
└── kubernetes/
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── prometheus/
    │   ├── prometheus-app.yaml         # ArgoCD Application
    │   └── prometheus-values.yaml      # Helm values
    ├── victoria-metrics/
    │   ├── victoria-metrics-app.yaml
    │   ├── victoria-metrics-pv.yaml
    │   └── victoria-metrics-values.yaml
    ├── victoria-logs/
    │   ├── victoria-logs-app.yaml
    │   ├── victoria-logs-pv.yaml
    │   └── victoria-logs-values.yaml
    ├── grafana/
    │   ├── grafana-app.yaml
    │   ├── grafana-datasources.yaml
    │   └── grafana-dashboards/
    ├── alertmanager/
    │   ├── alertmanager-app.yaml
    │   └── alertmanager-config.yaml
    ├── beszel/
    │   ├── beszel-app.yaml
    │   └── beszel-deployment.yaml
    ├── gatus/
    │   ├── gatus-app.yaml
    │   └── gatus-configmap.yaml
    └── ingress/
        └── traefik-routes.yaml
```

**Deployment:**
```bash
# Push to GitHub
cd /home/monit_homelab
git add kubernetes/
git commit -m "Phase 2: Add monitoring stack manifests"
git push origin main

# Register cluster with ArgoCD (from prod cluster)
argocd cluster add monitoring-k3s \
  --kubeconfig ~/.kube/monitoring-k3s.yaml \
  --name monitoring-k3s

# Deploy via ArgoCD ApplicationSet (runs on prod ArgoCD)
kubectl apply -f /home/prod_homelab/kubernetes/argocd/multi-repo-appset.yaml
```

---

### 🔄 Phase 3: Integration & Monitoring Targets (FUTURE)

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
| TrueNAS (Carrick) | TrueNAS API | 10.40.0.10 | 443 | Storage, NVMe-oF stats |

**Beszel Agents:** Deploy to all hosts for resource monitoring
**Gatus Endpoints:** Configure health checks for all services

---

### 🔄 Phase 4: External Monitoring (OPTIONAL)

**What:** Deploy external VPS for outside-in monitoring

**Setup:**
- VPS ($5/month, e.g., Oracle Cloud Free Tier, Hetzner)
- Gatus container monitoring production from outside
- Detects ISP/network failures
- Alerts when prod cluster is unreachable from internet

---

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ Management Network (vmbr0): 10.10.0.0/24                        │
│ ├─ Proxmox Ruapehu: 10.10.0.10                                 │
│ ├─ Talos Control Plane: 10.10.0.40                             │
│ ├─ Talos Workers: 10.10.0.41-43                                │
│ ├─ Plex VM: 10.10.0.50                                         │
│ └─ OPNsense/AdGuard: 10.10.0.1                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↕ Isolated
┌─────────────────────────────────────────────────────────────────┐
│ Monitoring Network (vmbr0): 10.30.0.0/24                       │
│ ├─ Proxmox Carrick: 10.30.0.10                                 │
│ └─ K3s Monitor: 10.30.0.20                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ TrueNAS Network (vmbr3): 10.40.0.0/24                          │
│ └─ TrueNAS (on Carrick): 10.40.0.10                            │
│    └─ NVMe-oF Exports: Restormal, Trelawney                    │
└─────────────────────────────────────────────────────────────────┘
```

**Network Routing:**
- K3s Monitor (10.30.0.20) can scrape Production (10.10.0.0/24) via routing
- K3s Monitor can mount NFS from TrueNAS (10.40.0.10) via vmbr3
- Production cluster cannot reach monitoring (one-way monitoring)

---

## Storage Strategy

### VictoriaMetrics (200GB on Restormal)

**Why:** Time-series metrics database
- Prometheus-compatible
- Efficient compression
- Fast queries
- 200GB for ~1 year retention at 1-minute scrape interval

**NFS Mount:**
```yaml
nfs:
  server: 10.40.0.10
  path: /mnt/Restormal/victoria-metrics
```

### VictoriaLogs (500GB on Trelawney)

**Why:** Log aggregation and search
- Stores logs from all pods/hosts
- Full-text search
- 500GB for ~6 months retention

**NFS Mount:**
```yaml
nfs:
  server: 10.40.0.10
  path: /mnt/Trelawney/victoria-logs
```

### Why NVMe-oF on TrueNAS?

- **Performance:** NVMe-backed storage for fast time-series writes
- **Reliability:** ZFS checksums, snapshots, replication
- **Centralized:** All monitoring storage in one place
- **Scalable:** Easy to expand NVMe pools

---

## Security Considerations

### Secrets Management (Infisical)

All sensitive values stored in Infisical `/monitoring` folder:

| Secret | Purpose |
|--------|---------|
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin login |
| `ALERTMANAGER_SLACK_WEBHOOK` | Slack alert notifications |
| `ALERTMANAGER_DISCORD_WEBHOOK` | Discord alert notifications |
| `BESZEL_API_KEY` | Beszel agent authentication |
| `GATUS_API_KEY` | Gatus API access |
| `GITHUB_PAT` | ArgoCD repository access |
| `CLOUDFLARE_TUNNEL_TOKEN` | Cloudflare Tunnel for external access |

### Network Isolation

- Monitoring on separate subnet (10.30.0.0/24)
- One-way traffic (monitoring scrapes production, not reverse)
- Firewall rules limit ingress to monitoring LXC

### SSH Keys

- LXC root access via ed25519 key only
- Password authentication disabled
- Key managed via Terraform variable

---

## Manual Steps Before Phase 2

### 1. Verify TrueNAS is Ready

```bash
# SSH to TrueNAS (on Carrick, e.g., 10.40.0.10)
ssh root@10.40.0.10

# Check NVMe-oF exports
zfs list | grep -E 'Restormal|Trelawney'

# Create datasets if needed
zfs create tank/Restormal/victoria-metrics
zfs create tank/Trelawney/victoria-logs

# Configure NFS exports
# TrueNAS UI → Sharing → NFS
# Add: /mnt/Restormal/victoria-metrics → Allow 10.30.0.20/32
# Add: /mnt/Trelawney/victoria-logs → Allow 10.30.0.20/32
```

### 2. Test NFS Mounts from K3s

```bash
# SSH to K3s LXC
ssh root@10.30.0.20

# Install NFS client
apt-get update && apt-get install -y nfs-common

# Test mount
showmount -e 10.40.0.10
# Should show:
# /mnt/Restormal/victoria-metrics 10.30.0.20
# /mnt/Trelawney/victoria-logs 10.30.0.20

# Test actual mount
mkdir -p /mnt/test-restormal
mount -t nfs 10.40.0.10:/mnt/Restormal/victoria-metrics /mnt/test-restormal
df -h | grep restormal
# Should show mounted filesystem

# Cleanup
umount /mnt/test-restormal
```

### 3. Register Cluster with ArgoCD

```bash
# From your workstation with access to prod ArgoCD
argocd login argocd.kernow.io --username admin

# Add monitoring cluster
argocd cluster add monitoring-k3s \
  --kubeconfig ~/.kube/monitoring-k3s.yaml \
  --name monitoring-k3s

# Verify
argocd cluster list
# Should show both in-cluster (prod) and monitoring-k3s
```

### 4. Create Infisical Secrets

**In Infisical UI** (https://app.infisical.com):
1. Project: `prod_homelab`
2. Environment: `prod`
3. Create folder: `/monitoring`
4. Add secrets (see Security Considerations above)

---

## Success Criteria

### Phase 1 (Current) ✅

- [x] K3s LXC running on Proxmox Carrick
- [x] Kubeconfig works: `kubectl --kubeconfig ~/.kube/monitoring-k3s.yaml get nodes`
- [x] SSH access: `ssh root@10.30.0.20`
- [x] Terraform configuration valid and documented
- [x] Git repository initialized and committed

### Phase 2 (Next) 🔄

- [ ] All monitoring pods running in `monitoring` namespace
- [ ] VictoriaMetrics has 200GB PV mounted from Restormal
- [ ] VictoriaLogs has 500GB PV mounted from Trelawney
- [ ] Grafana accessible and has VictoriaMetrics datasource
- [ ] Prometheus scraping all production targets
- [ ] AlertManager configured with Slack/Discord webhooks
- [ ] Beszel agents deployed on all hosts
- [ ] Gatus showing all endpoint statuses

### Phase 3 (Future) 🔄

- [ ] All production hosts reporting metrics
- [ ] Grafana dashboards for Proxmox, Talos, Plex, OPNsense
- [ ] Alerts firing correctly to Slack/Discord
- [ ] External VPS Gatus monitoring from outside
- [ ] Cloudflare DNS resolving to monitoring services

---

## Timeline Estimate

| Phase | Work | Duration |
|-------|------|----------|
| **Phase 1** (Done) | Terraform + K3s provision | 1 hour setup + 10 min deploy |
| **Phase 2** (Next) | Manifests + ArgoCD deploy | 2 hours setup + 20 min deploy |
| **Phase 3** (Later) | Configure scrape targets + agents | 2 hours spread over days |
| **Total** | — | ~5-6 hours active work |

---

## References

- **Phase 1 README**: `/home/monit_homelab/README.md`
- **Environment Setup**: `/home/monit_homelab/ENVIRONMENT_VARIABLES.md`
- **Deployment Summary**: `/home/monit_homelab/DEPLOYMENT_SUMMARY.md`
- **Production Reference**: `/home/prod_homelab/`
- **Proxmox Carrick**: `ssh root@10.30.0.10`
- **K3s Cluster**: `ssh root@10.30.0.20`
