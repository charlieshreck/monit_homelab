# Talos MCP Server

MCP server for managing Talos Linux nodes in the production cluster.

## Manual Setup Required

The talosconfig is NOT committed to git for security.

Create the ConfigMap manually:

```bash
kubectl create configmap talosconfig \
  --from-file=talosconfig=/home/prod_homelab/infrastructure/terraform/generated/talosconfig \
  -n mcp-servers
```

Or copy from your local machine:

```bash
scp /home/prod_homelab/infrastructure/terraform/generated/talosconfig root@10.30.0.20:/tmp/talosconfig
ssh root@10.30.0.20
kubectl create configmap talosconfig \
  --from-file=talosconfig=/tmp/talosconfig \
  -n mcp-servers
rm /tmp/talosconfig
```

## Usage

Once deployed, you can query:

- "Check health of all Talos nodes"
- "Show etcd cluster status"
- "Get logs from talos-worker-1"
- "Show disk usage on all Talos nodes"
- "Get Talos version on all nodes"
- "Check Talos services status"
