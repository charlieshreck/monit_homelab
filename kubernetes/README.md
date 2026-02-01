# Monitoring Stack - Kubernetes Manifests

Kubernetes manifests for the monitoring infrastructure deployed on the Talos Linux cluster at 10.10.0.30.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Production ArgoCD (10.10.0.0/24)                                │
│ └─ Manages monitoring cluster via registered context           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Monitoring Talos Cluster (10.10.0.30)                           │
│ Talos Linux v1.11.5 + Kubernetes v1.34.1 + Cilium              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Namespace: monitoring                                       │ │
│ │ ├─ Prometheus (metrics scraping)                           │ │
│ │ ├─ VictoriaMetrics (200GB NFS - 12mo retention)           │ │
│ │ ├─ VictoriaLogs (500GB NFS - 6mo retention)               │ │
│ │ ├─ Grafana (dashboards + datasources)                     │ │
│ │ ├─ AlertManager (alerts routing)                          │ │
│ │ ├─ Coroot (eBPF observability)                            │ │
│ │ ├─ Beszel (host monitoring)                               │ │
│ │ └─ Gatus (endpoint health checks)                         │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ TrueNAS-M (10.30.0.120)                                        │
│ ├─ /mnt/Restormal/victoria-metrics (200GB)                     │
│ └─ /mnt/Trelawney/victoria-logs (500GB)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
kubernetes/
├── bootstrap/
│   └── app-of-apps.yaml           # Root ArgoCD Application
├── argocd-apps/
│   └── platform/
│       ├── storage-app.yaml              # NFS PVs for VictoriaMetrics/Logs
│       ├── kube-prometheus-stack-app.yaml # Prometheus + Grafana + AlertManager
│       ├── victoria-metrics-app.yaml      # Long-term metrics storage
│       ├── victoria-logs-app.yaml         # Log aggregation
│       ├── beszel-app.yaml                # Host monitoring
│       └── gatus-app.yaml                 # Endpoint status checks
└── platform/
    ├── monitoring-namespace.yaml
    ├── storage/
    │   ├── victoria-metrics-pv.yaml
    │   └── victoria-logs-pv.yaml
    ├── beszel/
    │   └── deployment.yaml
    └── gatus/
        └── deployment.yaml
```

## Deployment Process

### Prerequisites

1. **Talos cluster running** at 10.10.0.30 (deployed via Terraform)
2. **TrueNAS NFS exports** configured:
   - `/mnt/Restormal/victoria-metrics` accessible from 10.10.0.30
   - `/mnt/Trelawney/victoria-logs` accessible from 10.10.0.30
3. **Production ArgoCD** accessible (on production cluster)
4. **Git repository** pushed to GitHub

### Step 1: Configure TrueNAS NFS Exports

```bash
# SSH to TrueNAS at 10.30.0.120
ssh root@10.30.0.120

# Create ZFS datasets
zfs create tank/Restormal/victoria-metrics
zfs create tank/Trelawney/victoria-logs

# Set permissions
chmod 777 /mnt/Restormal/victoria-metrics
chmod 777 /mnt/Trelawney/victoria-logs

# Configure NFS exports in TrueNAS UI:
# Sharing → NFS → Add
# Path: /mnt/Restormal/victoria-metrics
# Networks: 10.10.0.30/32
# Maproot User: root
# Maproot Group: root
# Repeat for Trelawney
```

### Step 2: Verify NFS Access

```bash
# From the iac LXC or any host that can reach the NFS server
# Note: Talos is immutable - you cannot SSH to it or install packages on it
# Test NFS from a machine that has nfs-common installed:
showmount -e 10.30.0.120
# Should show:
#   /mnt/Restormal/victoria-metrics 10.10.0.30
#   /mnt/Trelawney/victoria-logs 10.10.0.30
```

### Step 3: Push to GitHub

```bash
cd /home/monit_homelab

# Stage all changes
git add kubernetes/

# Commit
git commit -m "Add monitoring stack Kubernetes manifests"

# Push to GitHub
git push origin main
```

### Step 4: Register Monitoring Cluster with Production ArgoCD

```bash
# From iac LXC (10.10.0.175) with kubectl access to prod cluster
export KUBECONFIG=$KUBECONFIG_PROD

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Login to ArgoCD CLI
argocd login <production-argocd-url> --username admin

# Register monitoring cluster
argocd cluster add monitoring-cluster \
  --kubeconfig /home/monit_homelab/kubeconfig \
  --name monitoring-cluster

# Verify registration
argocd cluster list
```

### Step 5: Deploy App-of-Apps

```bash
# Apply the root Application to production ArgoCD
# (This is one of the rare manual kubectl apply exceptions)
kubectl apply -f kubernetes/bootstrap/app-of-apps.yaml

# Watch deployment
kubectl get applications -n argocd -w

# Check sync status
argocd app list
```

### Step 6: Verify Deployment

```bash
# Switch to monitoring cluster
export KUBECONFIG=/home/monit_homelab/kubeconfig

# Check namespace
kubectl get namespace monitoring

# Check storage
kubectl get pv
kubectl get pvc -n monitoring

# Check pods
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring
```

## Access Applications

### Grafana

```bash
# Via ingress
# https://grafana.kernow.io

# Or port forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Access: http://localhost:3000
```

**Datasources (pre-configured):**
- Prometheus (default): http://kube-prometheus-stack-prometheus:9090
- VictoriaMetrics: http://victoria-metrics:8428
- VictoriaLogs: http://victoria-logs:9428

### Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Access: http://localhost:9090
```

### Gatus Status Page

```bash
kubectl port-forward -n monitoring svc/gatus 8080:8080
# Access: http://localhost:8080
```

### Beszel Dashboard

```bash
kubectl port-forward -n monitoring svc/beszel 8090:8090
# Access: http://localhost:8090
```

## Monitoring Targets

Prometheus is configured to scrape:

| Target | Address | Metrics | Notes |
|--------|---------|---------|-------|
| **Proxmox Ruapehu** | 10.10.0.10:8006 | Proxmox VE metrics | Production hypervisor |
| **Proxmox Carrick** | 10.30.0.10:8006 | Proxmox VE metrics | Monitoring hypervisor |
| **Talos Monitor** | 10.10.0.30:10250 | Kubelet metrics | Monitoring cluster node |
| **Talos Cluster** | 10.10.0.40-43 | Kubernetes metrics | Production cluster nodes |

## Storage Details

### VictoriaMetrics (200GB)

- **Path**: `/mnt/Restormal/victoria-metrics` on TrueNAS
- **Retention**: 12 months
- **PV**: `victoria-metrics-pv`
- **PVC**: `victoria-metrics-storage`
- **Mount**: `/storage` in pod

### VictoriaLogs (500GB)

- **Path**: `/mnt/Trelawney/victoria-logs` on TrueNAS
- **Retention**: 6 months
- **PV**: `victoria-logs-pv`
- **PVC**: `victoria-logs-storage`
- **Mount**: `/storage` in pod

## Troubleshooting

### Pods stuck in Pending

```bash
# Check events
kubectl describe pod -n monitoring <pod-name>

# Common causes:
# - PVC not bound (check NFS exports)
# - Insufficient resources
# - Image pull errors
```

### NFS mount failures

```bash
# Check PV status
kubectl describe pv victoria-metrics-pv
kubectl describe pv victoria-logs-pv

# Verify NFS from a Linux host (NOT from Talos - it has no shell)
showmount -e 10.30.0.120

# Test mount from iac LXC
mount -t nfs 10.30.0.120:/mnt/Restormal/victoria-metrics /mnt/test
```

### ArgoCD sync issues

```bash
# Check Application status (from prod cluster)
export KUBECONFIG=$KUBECONFIG_PROD
kubectl get application -n argocd monitoring-platform -o yaml

# Manual sync
argocd app sync monitoring-platform

# Force sync
argocd app sync monitoring-platform --force
```

### VictoriaMetrics not receiving data

```bash
# Check remote write from Prometheus
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 | grep remote

# Test VictoriaMetrics API
kubectl exec -n monitoring -it <victoria-metrics-pod> -- curl localhost:8428/api/v1/query?query=up
```

## Maintenance

### Backup VictoriaMetrics/Logs Data

Data is on TrueNAS NFS - use ZFS snapshots:

```bash
# On TrueNAS
zfs snapshot tank/Restormal/victoria-metrics@backup-$(date +%Y%m%d)
zfs snapshot tank/Trelawney/victoria-logs@backup-$(date +%Y%m%d)

# List snapshots
zfs list -t snapshot
```

### Update Applications

Applications auto-update via ArgoCD when:
1. Helm chart version is updated in ArgoCD Application manifest
2. Kubernetes manifests change in Git repo

Manual sync:
```bash
argocd app sync <app-name>
```

## Resources

- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [VictoriaMetrics](https://github.com/VictoriaMetrics/helm-charts)
- [VictoriaLogs](https://docs.victoriametrics.com/VictoriaLogs/)
- [Beszel](https://github.com/henrygd/beszel)
- [Gatus](https://github.com/TwinProduction/gatus)
- [ArgoCD](https://argo-cd.readthedocs.io/)
