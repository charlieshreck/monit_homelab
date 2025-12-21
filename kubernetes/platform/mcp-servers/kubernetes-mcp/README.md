# Kubernetes MCP Servers

MCP servers for managing both production Talos cluster and monitoring K3s cluster.

## Production Cluster

**Manual Setup Required**: The production kubeconfig is NOT committed to git for security.

Create the ConfigMap manually:

```bash
kubectl create configmap kubeconfig-prod \
  --from-file=kubeconfig=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig \
  -n mcp-servers
```

Or copy from your local machine:

```bash
scp /home/prod_homelab/infrastructure/terraform/generated/kubeconfig root@10.30.0.20:/tmp/kubeconfig-prod
ssh root@10.30.0.20
kubectl create configmap kubeconfig-prod \
  --from-file=kubeconfig=/tmp/kubeconfig-prod \
  -n mcp-servers
rm /tmp/kubeconfig-prod
```

## Monitoring Cluster

Uses in-cluster ServiceAccount authentication (no kubeconfig needed).
The `mcp-kubernetes` ServiceAccount has view-only permissions via ClusterRoleBinding.

## Usage

Once deployed, you can query:

**Production cluster:**
- "List all pods in argocd namespace on production cluster"
- "Show failing deployments in prod cluster"
- "Get logs from homepage pod"

**Monitoring cluster:**
- "List all pods in monitoring namespace"
- "Show coroot deployment status"
- "Check victoria-metrics pods"
