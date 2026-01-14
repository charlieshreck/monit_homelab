# Coroot Agent - Agentic Cluster

Deploys Coroot agents to the agentic cluster (10.20.0.0/24) for comprehensive eBPF-based observability.

## Components

1. **Cluster Agent** (Deployment)
   - Collects Kubernetes metadata and metrics
   - Includes kube-state-metrics sidecar
   - Reports to Coroot at 10.30.0.20:32702

2. **Node Agent** (DaemonSet)
   - eBPF-based observability
   - Collects container metrics, traces, and profiles
   - Runs in privileged mode for eBPF access

## Deployment

Deployed via ArgoCD to agentic cluster:
- Application: `coroot-agent-agentic`
- Destination: https://10.20.0.40:6443

## Secret Management

API key stored in Infisical:
- Path: `/monitoring/coroot`
- Key: `agentic_apikey`
- InfisicalSecret creates `coroot-agent-apikey` in `coroot-agent` namespace

## Coroot Server Configuration

The agentic-homelab project is configured in the Coroot CR:
- File: `/home/monit_homelab/kubernetes/platform/coroot-config/coroot-cr.yaml`
- Secret: `agentic-homelab-api-key` in `coroot` namespace

## Verification

```bash
# Check agents are running
export KUBECONFIG=/home/agentic_lab/infrastructure/terraform/talos-cluster/generated/kubeconfig
kubectl get pods -n coroot-agent

# Check Coroot UI
# Navigate to http://10.30.0.20:32702
# Select "agentic-homelab" project
```
