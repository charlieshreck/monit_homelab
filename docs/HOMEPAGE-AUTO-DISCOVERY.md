# Homepage Auto-Discovery for Monitoring Cluster

**Date**: 2025-12-18
**Status**: ✅ Complete

## Overview

Implemented automatic service discovery in Homepage dashboard for monitoring cluster services. Homepage running in the production cluster (10.10.0.40) now automatically discovers and displays all monitoring services running in the dedicated monitoring cluster (10.30.0.20) via ingress annotations.

## Architecture

```
Homepage (prod cluster: 10.10.0.40)
    ↓ (discovers via annotations on ingresses)
Cloudflare Tunnel Ingress (prod cluster)
    ↓ (routes to)
External Service (ClusterIP, port 80)
    ↓ (backed by)
Manual Endpoints (10.30.0.90:80 - Traefik LB)
    ↓ (routes to via Host header)
Monitoring Cluster Traefik Ingress (10.30.0.90)
```

## Implementation Details

### 1. Homepage RBAC in Monitoring Cluster

**Location**: `/home/monit_homelab/kubernetes/platform/homepage-rbac/`

Created ServiceAccount, ClusterRole, and Secret to allow Homepage (running in prod cluster) to query the monitoring cluster's Kubernetes API for multi-cluster discovery.

**Permissions**:
- Read namespaces, pods, nodes
- Read services, ingresses
- Read deployments, statefulsets, daemonsets
- Read metrics (CPU/memory)

**Deployed to**: Monitoring cluster (10.30.0.20:6443) in `homepage` namespace

### 2. Multi-Cluster Configuration in Production

**Location**: `/home/prod_homelab/kubernetes/applications/apps/homepage/config.yaml`

**kubernetes.yaml**:
```yaml
mode: cluster

clusters:
  - name: production
    url: https://10.10.0.40:6443

  - name: monitoring
    url: https://10.30.0.20:6443
    serviceAccountToken: /app/monitoring/token
    certificate: /app/monitoring/ca
```

**Credentials mounted**: Monitoring cluster kubeconfig secret at `/app/monitoring/` in Homepage pod

### 3. External Services in Production Cluster

**Location**: `/home/prod_homelab/kubernetes/applications/apps/monitoring-external/`

Created three manifest files:

#### services.yaml
ClusterIP services without selectors (no pods in prod cluster):
- grafana-external, prometheus-external, alertmanager-external
- victoriametrics-external, victorialogs-external
- gatus-external, beszel-external, coroot-external

#### endpoints.yaml
Manual Endpoints objects pointing to monitoring cluster Traefik LB:
```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: grafana-external
  namespace: apps
subsets:
  - addresses:
      - ip: 10.30.0.90
    ports:
      - name: http
        port: 80
        protocol: TCP
```

**Mapping** (all route via Traefik Host header):
- grafana-external:80 → 10.30.0.90:80 (grafana.kernow.io)
- prometheus-external:80 → 10.30.0.90:80 (prometheus.kernow.io)
- alertmanager-external:80 → 10.30.0.90:80 (alertmanager.kernow.io)
- victoriametrics-external:80 → 10.30.0.90:80 (victoria-metrics.kernow.io)
- victorialogs-external:80 → 10.30.0.90:80 (victoria-logs.kernow.io)
- gatus-external:80 → 10.30.0.90:80 (gatus.kernow.io)
- beszel-external:80 → 10.30.0.90:80 (beszel.kernow.io)
- coroot-external:80 → 10.30.0.90:80 (coroot.kernow.io)

#### cloudflare-tunnel-ingresses.yaml
Ingress resources with Homepage auto-discovery annotations:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-cloudflare
  namespace: apps
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Grafana"
    gethomepage.dev/group: "Monitoring"
    gethomepage.dev/icon: "grafana.png"
    gethomepage.dev/description: "Metrics Dashboards"
    gethomepage.dev/ping: "http://grafana-external"
    gethomepage.dev/pod-selector: ""
spec:
  ingressClassName: cloudflare-tunnel
  rules:
    - host: grafana.kernow.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana-external
                port:
                  number: 80
```

**Key Annotations**:
- `gethomepage.dev/enabled: "true"` - Enable auto-discovery
- `gethomepage.dev/name` - Service name displayed in Homepage
- `gethomepage.dev/group` - Section to group service in (Monitoring)
- `gethomepage.dev/icon` - Icon to display
- `gethomepage.dev/description` - Service description
- `gethomepage.dev/ping` - HTTP health check URL (internal service)
- `gethomepage.dev/pod-selector: ""` - Disable Kubernetes pod status checks
- `gethomepage.dev/widget.type` - Widget type (prometheus, gatus, beszel)
- `gethomepage.dev/widget.url` - Widget data source URL
- `gethomepage.dev/widget.key` - Widget API key (for beszel)

### 4. Services Deployed

All services auto-discovered in the **Monitoring** group:

1. **AlertManager** - Alert Routing (alertmanager.kernow.io)
2. **Beszel** - Host Monitoring + widget (beszel.kernow.io)
3. **Coroot** - eBPF Observability (coroot.kernow.io)
4. **Gatus** - Health Checks + widget (gatus.kernow.io)
5. **Grafana** - Metrics Dashboards (grafana.kernow.io)
6. **Prometheus** - Metrics Collection + widget (prometheus.kernow.io)
7. **VictoriaLogs** - Log Aggregation (victoria-logs.kernow.io)
8. **VictoriaMetrics** - Time Series Database (victoria-metrics.kernow.io)

### 5. Monitoring Cluster Widget Fix

**Problem**: Second kubernetes widget in Homepage info bar showed production cluster stats despite label "Monitoring Cluster"

**Solution**: Added `clusterName: "monitoring"` to widgets.yaml

```yaml
- kubernetes:
    cluster:
      show: true
      cpu: true
      memory: true
      showLabel: true
      label: "Monitoring Cluster"
    nodes:
      show: true
      cpu: true
      memory: true
      showLabel: true
    clusterName: "monitoring"
```

Now displays:
- **Application Cluster** - Production cluster (10.10.0.40) stats
- **Monitoring Cluster** - Monitoring cluster (10.30.0.20) stats

## Issues Encountered and Solutions

### Issue 1: Services had no endpoints (502 errors)

**Problem**: Initial approach used `externalIPs` without selectors, creating services with no endpoints. Cloudflare Tunnel returned 502 errors.

**Solution**: Created manual Endpoints objects with `addresses: [10.30.0.20]` and specific NodePort numbers.

### Issue 2: Status checks showing offline

**Problem**: Homepage showed services as "offline" despite working routing. Homepage was trying to find pods in production cluster.

**Solution**: Added `gethomepage.dev/ping` annotations pointing to internal service URLs that Homepage can reach from within the prod cluster.

### Issue 3: Kubernetes pod status errors in logs

**Problem**: Homepage logs showed errors: `no pods found with namespace=apps and labelSelector=app.kubernetes.io/name=grafana-cloudflare`

**Solution**: Added `gethomepage.dev/pod-selector: ""` (empty string) to disable Kubernetes pod status checks and rely solely on ping URLs.

### Issue 4: Duplicate monitoring services

**Problem**: Old hardcoded monitoring services remained in services.yaml after adding auto-discovery.

**Solution**: Removed hardcoded entries from config.yaml services.yaml section. Widgets preserved via ingress annotations.

### Issue 5: Monitoring cluster widget showing wrong cluster

**Problem**: Second kubernetes widget defaulted to production cluster despite label.

**Solution**: Added `clusterName: "monitoring"` to explicitly specify which cluster to query.

## ArgoCD Applications

### Production Cluster

**monitoring-external-app.yaml**:
- Project: default
- Source: prod_homelab.git/kubernetes/applications/apps/monitoring-external
- Destination: Production cluster (10.10.0.40) apps namespace
- Sync: Automated with prune and selfHeal

### Monitoring Cluster

**homepage-rbac-app.yaml**:
- Project: default
- Source: monit_homelab.git/kubernetes/platform/homepage-rbac
- Destination: Monitoring cluster (10.30.0.20) homepage namespace
- Sync: Automated with prune and selfHeal

## Verification

```bash
# Check external service endpoints exist
kubectl get endpoints -n apps | grep external

# Verify ingress annotations
kubectl get ingress -n apps grafana-cloudflare -o yaml | grep gethomepage

# Test external access
curl -I https://grafana.kernow.io

# Check Homepage logs
kubectl logs -n apps -l app.kubernetes.io/name=homepage --tail=50

# Count services by group (check for duplicates)
kubectl get ingress -n apps -o json | jq -r '.items[] |
  select(.metadata.annotations."gethomepage.dev/enabled" == "true") |
  "\(.metadata.annotations."gethomepage.dev/group"): \(.metadata.annotations."gethomepage.dev/name")"' |
  sort | uniq -c
```

## Benefits

1. **Single Source of Truth**: Service definitions via ingress annotations (no hardcoded config)
2. **External Access**: All monitoring services accessible via Cloudflare Tunnel
3. **Status Monitoring**: HTTP ping checks show real-time service status
4. **Widgets**: Prometheus, Gatus, and Beszel widgets provide live metrics
5. **Multi-Cluster**: Homepage queries both production and monitoring clusters
6. **GitOps**: All configuration version controlled and managed via ArgoCD

## Related Documentation

- Homepage discovery: https://gethomepage.dev/
- Multi-cluster setup: `/home/prod_homelab/CLAUDE.md`
- Monitoring infrastructure: `/home/monit_homelab/README.md`

## Commits

1. `2f4b647` - Enable Homepage auto-discovery for monitoring cluster services
2. `f703931` - Fix monitoring external services with manual endpoints
3. `fe137b2` - Add ping URLs to monitoring service ingress annotations
4. `6fdf8b4` - Disable Kubernetes pod status checks for monitoring services
5. `d6b2eae` - Move Coroot from Platform Services to Monitoring group
6. `a718a20` - Fix monitoring cluster kubernetes widget configuration
