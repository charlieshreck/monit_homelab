# Coroot Deployment Status

## Current Status

Coroot has been deployed to the monitoring cluster with **temporary manual Helm installations** to get it working immediately. The proper GitOps configuration is now in place for future management.

### What's Running Now (Manual Helm Deployments)

On **monit_homelab** cluster (10.30.0.20):
```bash
# Installed via Helm (temporary)
helm list -n coroot
NAME            NAMESPACE  REVISION  STATUS    CHART                     APP VERSION
coroot          coroot     1         deployed  coroot-ce-0.14.3          1.13.0
coroot-operator coroot     1         deployed  coroot-operator-0.15.0    0.15.0
```

Agents deployed on both clusters:
- **prod_homelab** (10.10.0.40) - monitoring production workloads
- **monit_homelab** (10.30.0.20) - monitoring monitoring infrastructure

### What's in Git (IaC/GitOps)

All Coroot configuration is now version controlled:

**ArgoCD Applications** (ready for deployment):
- `kubernetes/argocd-apps/platform/coroot-operator-app.yaml` - Coroot operator
- `kubernetes/argocd-apps/platform/coroot-server-app.yaml` - Coroot CE server
- `kubernetes/argocd-apps/platform/coroot-agent-prod-app.yaml` - Prod cluster agents
- `kubernetes/argocd-apps/platform/coroot-agent-local-app.yaml` - Monitoring cluster agents

**Platform Manifests**:
- `kubernetes/platform/coroot-agent-prod/manifests.yaml` - Production agents
- `kubernetes/platform/coroot-agent-local/manifests.yaml` - Local agents

**Committed**: `85ebc93` - "Add Coroot multi-cluster observability platform"

## Access

- **Coroot UI**: http://10.30.0.90:8080
- **Projects**:
  - Production: http://10.30.0.90:8080/p/prod-homelab
  - Monitoring: http://10.30.0.90:8080/p/monit-homelab
  - Aggregated View: http://10.30.0.90:8080/p/all-clusters

## Next Steps: Transition to GitOps

Once ArgoCD is deployed on the monitoring cluster:

### Option 1: Clean Slate (Recommended)

1. **Remove manual Helm deployments**:
```bash
export KUBECONFIG=/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig

# Remove Coroot server and operator
helm uninstall coroot -n coroot
helm uninstall coroot-operator -n coroot

# Remove manually deployed agents
kubectl delete namespace coroot-agent

# Clean up on prod cluster
export KUBECONFIG=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig
kubectl delete namespace coroot-agent
```

2. **Deploy via ArgoCD**:
```bash
export KUBECONFIG=/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig

# Apply ArgoCD applications
kubectl apply -f kubernetes/argocd-apps/platform/coroot-operator-app.yaml
kubectl apply -f kubernetes/argocd-apps/platform/coroot-server-app.yaml
kubectl apply -f kubernetes/argocd-apps/platform/coroot-agent-local-app.yaml
kubectl apply -f kubernetes/argocd-apps/platform/coroot-agent-prod-app.yaml

# Watch ArgoCD sync
kubectl get applications -n argocd -w
```

### Option 2: App-of-Apps Pattern (Automatic)

If you're using the app-of-apps pattern (monitoring-platform application), ArgoCD will automatically discover and deploy all applications in `kubernetes/argocd-apps/platform/`:

```bash
# Just apply the app-of-apps
kubectl apply -f kubernetes/bootstrap/app-of-apps.yaml

# ArgoCD will automatically sync:
# - coroot-operator (sync-wave: 1)
# - coroot-server (sync-wave: 2)
# - coroot-agent-local (sync-wave: 3)
# - coroot-agent-prod (sync-wave: 3)
```

The sync waves ensure proper ordering:
1. Operator installs first
2. Server installs after operator is ready
3. Agents install after server is running

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Coroot Server (monit_homelab cluster - 10.30.0.90:8080)    │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ • Coroot CE (Community Edition)                         │ │
│ │ • ClickHouse (metrics storage backend)                  │ │
│ │ • Prometheus (metrics collection)                       │ │
│ │ • Projects: prod-homelab, monit-homelab, all-clusters   │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                               ↑                     ↑
                               │                     │
        ┌──────────────────────┴────────┬────────────┴─────────────┐
        │                               │                           │
┌───────────────────┐          ┌────────────────────┐     ┌────────────────────┐
│ Agents            │          │ Agents             │     │ Agents             │
│ (prod_homelab)    │          │ (monit_homelab)    │     │ (Future clusters)  │
│ 10.10.0.40        │          │ 10.30.0.20         │     │                    │
│                   │          │                    │     │                    │
│ • Cluster Agent   │          │ • Cluster Agent    │     │ • Cluster Agent    │
│ • Node Agent      │          │ • Node Agent       │     │ • Node Agent       │
│   (eBPF)          │          │   (eBPF)           │     │   (eBPF)           │
└───────────────────┘          └────────────────────┘     └────────────────────┘
```

## Features

- **Zero-instrumentation observability**: eBPF-based automatic discovery
- **Multi-cluster monitoring**: Centralized view of both clusters
- **Service mesh visualization**: Automatic service dependency mapping
- **Metrics + Logs + Traces + Profiling**: Complete observability stack
- **AI-powered root cause analysis**: Intelligent issue detection

## Monitoring Scope

### prod_homelab Cluster
- Talos control plane + 3 workers
- Plex Media Server with GPU transcoding
- Production applications (Traefik, cert-manager, etc.)
- Mayastor storage
- NFS mounts from TrueNAS

### monit_homelab Cluster
- K3s single-node cluster
- Monitoring stack (Prometheus, Grafana, VictoriaMetrics/Logs)
- Beszel, Gatus
- Coroot itself (self-monitoring)

## API Keys

API keys are auto-generated by the Coroot operator and stored in secrets:

```bash
export KUBECONFIG=/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig

# Production cluster key
kubectl get secret prod-homelab-api-key -n coroot \
  -o jsonpath='{.data.apikey}' | base64 -d

# Monitoring cluster key
kubectl get secret monit-homelab-api-key -n coroot \
  -o jsonpath='{.data.apikey}' | base64 -d
```

These are already configured in the agent manifests.

## Troubleshooting

### Check Coroot server status
```bash
export KUBECONFIG=/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig
kubectl get pods -n coroot
kubectl get svc -n coroot
kubectl logs -n coroot deployment/coroot-coroot
```

### Check agents on production cluster
```bash
export KUBECONFIG=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig
kubectl get pods -n coroot-agent
kubectl logs -n coroot-agent deployment/coroot-cluster-agent
```

### Check agents on monitoring cluster
```bash
export KUBECONFIG=/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig
kubectl get pods -n coroot-agent
kubectl logs -n coroot-agent deployment/coroot-cluster-agent
```

### Verify metrics collection
Check the Coroot UI at http://10.30.0.90:8080 and ensure both projects show data.

## References

- Coroot Documentation: https://docs.coroot.com/
- GitHub: https://github.com/coroot/coroot
- Operator Docs: https://docs.coroot.com/installation/k8s-operator/
