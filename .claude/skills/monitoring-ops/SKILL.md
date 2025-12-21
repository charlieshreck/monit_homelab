---
name: monitoring-ops
description: Monitoring infrastructure operations for monit_homelab. Use when managing Coroot, VictoriaMetrics, Grafana, K3s monitoring cluster, or investigating production issues.
allowed-tools: All
---

# Monitoring Infrastructure Operations

## Common Queries & Default Prompts

### Coroot Observability
- "Show me errors in the prod-homelab project from the last hour"
- "Analyze CPU usage across all pods in the argocd namespace"
- "Find slow requests in the production cluster"
- "Show distributed traces for the homepage service"
- "List all monitored applications and their health status"
- "Check ClickHouse storage usage for Coroot"

### VictoriaMetrics Queries
- "Query victoria-metrics for pod CPU usage in last 24 hours"
- "Show metric cardinality statistics"
- "Check victoria-metrics storage disk usage"
- "List all scraped targets and their status"
- "Show memory usage trends for monitoring namespace"

### K3s Monitoring Cluster
- "Show all pods in monitoring namespace"
- "Check PVC status for monitoring workloads"
- "List failing pods in the monitoring cluster"
- "Show ingress routes for monitoring UIs"
- "Check MCP server pod status"

### Infrastructure Health
- "Check health of all MCP servers"
- "Verify Infisical secret synchronization"
- "Show NFS mount status on monitoring cluster"
- "Check Coroot agents connectivity (prod + monitoring clusters)"

### Production Cluster Monitoring
- "Show errors from the homepage application"
- "Check ArgoCD application sync status"
- "List pods with high restart counts"
- "Show certificate expiration dates in prod cluster"

## Architecture Context

### Monitoring Cluster (10.30.0.0/24)
- **K3s Node**: 10.30.0.20 (single-node cluster on Proxmox Carrick)
- **Proxmox Host**: Carrick (10.30.0.10)
- **TrueNAS**: 10.30.0.120 (NFS storage backend)

### Monitoring Stack Components
- **Coroot**: Observability platform (NodePort 32702)
  - UI: http://10.30.0.20:32702
  - OTLP: http://10.30.0.20:30275
  - Projects: prod-homelab, monit-homelab, all-clusters
  - ClickHouse: 100Gi for traces/logs/profiles
  - External Prometheus: Victoria Metrics

- **VictoriaMetrics**: TSDB (200Gi local-path storage)
  - Endpoint: http://victoria-metrics-victoria-metrics-single-server.monitoring:8428

- **Grafana**: Visualization dashboards
- **Prometheus** (kube-prometheus-stack): K8s metrics
- **Beszel**: System monitoring
- **Gatus**: Uptime monitoring

### MCP Servers (NodePorts 30080-30089)
- 30080: infisical-mcp (secrets management)
- 30081: coroot-mcp (observability queries)
- 30082: proxmox-ruapehu-mcp (production host)
- 30083: proxmox-carrick-mcp (monitoring host)
- 30084: kubernetes-prod-mcp (production Talos cluster)
- 30085: kubernetes-monitoring-mcp (monitoring K3s cluster)
- 30086: talos-mcp (Talos OS management)
- 30087: opnsense-mcp (firewall)
- 30088: unifi-mcp (network)
- 30089: adguard-mcp (DNS filtering)

### Storage Architecture
- **NFS Provisioner**: Dynamic PVs (Restormal/nfs-provisioner)
- **Static NFS PVs**: Dedicated datasets on Trelawney pool
  - prometheus-nfs (TrueNAS-M 10.30.0.120)
  - grafana-nfs (TrueNAS-M)
  - beszel-nfs (TrueNAS-M)
  - gatus-nfs (TrueNAS-M)
  - alertmanager-nfs (TrueNAS-M)

### Production Cluster (10.10.0.0/24)
- **Talos Cluster**: 1 CP (10.10.0.40) + 3 workers (10.10.0.41-43)
- **Proxmox Host**: Ruapehu (10.10.0.10)
- **TrueNAS**: 10.10.0.100 (mgmt), 10.40.0.10 (NFS)

## Common Workflows

### 1. Investigate Production Issue
```
1. Query Coroot for application errors/latency:
   "Show errors in prod-homelab project for <app-name>"

2. Check logs via Coroot:
   "Show logs for <pod-name> in <namespace>"

3. Analyze distributed traces:
   "Show traces for slow requests to <service>"

4. Query historical metrics:
   "Show CPU/memory trends for <namespace> in last 6 hours"

5. Correlate with infrastructure:
   "Check Talos node health"
   "Show Proxmox resource usage on Ruapehu"
```

### 2. Verify Monitoring Stack Health
```
1. Check all components:
   "Show pod status for coroot, victoria-metrics, grafana, prometheus"

2. Verify storage:
   "Check PVC usage for monitoring workloads"
   "Show ClickHouse disk usage"

3. Check connectivity:
   "List all Coroot agent connections"
   "Verify Victoria Metrics scrape targets"

4. Test MCP servers:
   "Check health of all MCP server pods"
```

### 3. Add New Monitoring Target
```
1. Deploy Coroot agent:
   "Create Coroot agent deployment for <cluster>"

2. Add ServiceMonitor:
   "Create ServiceMonitor for <app> to scrape metrics"

3. Configure Grafana:
   "Import dashboard for <app>"

4. Setup alerts:
   "Create PrometheusRule for <app> alerts"
```

### 4. Troubleshoot MCP Server
```
1. Check pod status:
   "Show logs for <mcp-server>-mcp pod"

2. Verify credentials:
   "Check InfisicalSecret sync status in mcp-servers namespace"

3. Test connectivity:
   "Check if <mcp-server>-mcp can reach <target-system>"

4. Restart if needed:
   "Restart <mcp-server>-mcp deployment"
```

## Key Patterns

### InfisicalSecret Usage
All MCP server credentials come from Infisical:
- **Project**: prod-homelab-y-nij
- **Environment**: prod
- **Path**: `/mcp-credentials`

### Dual-Ingress Pattern
Monitoring UIs follow the dual-ingress pattern:
- Internal (Traefik): LAN access via *.kernow.io
- External (Cloudflare Tunnel): Internet access via Cloudflare

### GitOps Deployment
- All changes via git commits
- ArgoCD auto-sync enabled
- Never manual kubectl apply (except ConfigMaps for secrets)

## Access URLs

### Internal (LAN)
- Coroot: http://10.30.0.20:32702
- Grafana: https://grafana.kernow.io
- Prometheus: https://prometheus.kernow.io

### MCP Servers
All accessible via NodePort on 10.30.0.20:300XX

## Security Notes

- MCP server credentials stored in Infisical
- Kubeconfig/Talosconfig NOT committed to git (manual ConfigMaps)
- Coroot API key required for coroot-mcp
- Network policies isolate mcp-servers namespace
