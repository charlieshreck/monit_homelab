# Coroot Server Configuration

Deploys Coroot server on monitoring cluster using Custom Resource with external Prometheus integration.

## Architecture

- **External Prometheus**: Victoria Metrics (http://victoria-metrics-victoria-metrics-single-server.monitoring:8428)
- **NO built-in Prometheus**: Eliminates duplicate metric storage
- **ClickHouse**: 100Gi for eBPF traces/profiles/logs only (metrics in Victoria Metrics)
- **Server State**: 10Gi PVC for configuration/cache
- **Service**: NodePort 32702 (UI), 30275 (OTLP)

## Projects

- **prod-homelab**: Production Talos cluster (1 CP + 3 workers)
- **monit-homelab**: Monitoring Talos cluster (single node)
- **all-clusters**: Aggregated view

## Storage Allocation

Total Coroot storage: 140Gi
- ClickHouse keepers: 3 × 10Gi = 30Gi (Kerrier boot disk)
- ClickHouse shard: 100Gi (monitoring-storage disk)
- Server state: 10Gi (monitoring-storage disk)
- NO Prometheus: 0Gi (using Victoria Metrics)

## Deployment Order

1. Operator (sync-wave: 1) creates CRDs
2. Config (sync-wave: 2) creates Coroot CR → server, ClickHouse, projects
3. Agents (sync-wave: 3) connect to server

## Access

- UI: http://10.30.0.20:32702
- OTLP: http://10.30.0.20:30275
