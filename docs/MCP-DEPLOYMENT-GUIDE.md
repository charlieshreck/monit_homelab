# MCP Servers Deployment Guide

> **NOTE**: This guide is LEGACY. MCP servers have been consolidated into 6 domain MCPs
> running in the **agentic cluster** (ai-platform namespace). See `/home/mcp-servers/` and
> `/home/agentic_lab/CLAUDE.md` for current architecture.
>
> The monitoring cluster no longer hosts MCP servers. Observability services are accessed
> via Traefik ingress at `*.monit.kernow.io` (e.g., `coroot.monit.kernow.io`).

## Overview (Legacy)

MCP (Model Context Protocol) servers provide Claude Code with direct API access to all infrastructure components. MCP servers are now deployed in the agentic cluster and access monitoring services via DNS-based ingress.

## Current Architecture

```
Claude Code (IAC Container)
    │
    ├─ HTTP connections to domain MCPs on *.agentic.kernow.io
    │
    ↓
Agentic Cluster (10.20.0.40) — ai-platform namespace
├─ observability-mcp → Coroot (coroot.monit.kernow.io)
│                     → Grafana (grafana.monit.kernow.io)
│                     → VictoriaMetrics (victoriametrics.monit.kernow.io)
│                     → AlertManager (alertmanager.monit.kernow.io)
│                     → Gatus (gatus.monit.kernow.io)
├─ infrastructure-mcp → Kubernetes, Proxmox, TrueNAS, etc.
├─ knowledge-mcp → Qdrant, Neo4j, Outline
├─ home-mcp → Home Assistant, Tasmota, UniFi, AdGuard
├─ media-mcp → Plex, Sonarr, Radarr, etc.
└─ external-mcp → SearXNG, GitHub, Reddit, Wikipedia
```

## Prerequisites

### 1. Infisical Credentials

Add credentials to Infisical UI (Project: prod_homelab, Env: prod, Path: `/mcp-credentials`):

```bash
# Universal Auth (for Infisical MCP to read other secrets)
UNIVERSAL_AUTH_CLIENT_ID=<from Infisical UI: Settings → Machine Identities>
UNIVERSAL_AUTH_CLIENT_SECRET=<from Infisical UI>

# Proxmox
PROXMOX_USER=root@pam
PROXMOX_TOKEN_ID=terraform@pam!terraform
PROXMOX_TOKEN_SECRET=<your existing Proxmox API token>

# OPNsense
OPNSENSE_HOST=<opnsense-ip>
OPNSENSE_API_KEY=<generate in OPNsense UI: System → Settings → API>
OPNSENSE_API_SECRET=<generate in OPNsense UI>

# UniFi
UNIFI_HOST=<unifi-controller-ip>
UNIFI_USERNAME=<unifi-admin-username>
UNIFI_PASSWORD=<unifi-admin-password>

# AdGuard Home
ADGUARD_HOST=<adguard-ip>
ADGUARD_USERNAME=<adguard-username>
ADGUARD_PASSWORD=<adguard-password>

# Coroot
COROOT_BASE_URL=http://10.30.0.20:32702
COROOT_API_KEY=<get from Coroot UI: Settings → API Keys>
```

**How to get Infisical Universal Auth credentials:**
1. Go to Infisical → Project Settings → Machine Identities
2. Create new Machine Identity: "MCP Servers"
3. Add to Project: prod_homelab (Environment: prod)
4. Generate Client ID and Secret
5. Copy to Infisical path `/mcp-credentials`

**How to get Coroot API Key:**
1. Access Coroot UI: http://10.30.0.20:32702
2. Go to Settings → API Keys
3. Create new API key: "MCP Server"
4. Copy key to Infisical

### 2. Create Kubeconfig and Talosconfig ConfigMaps

These files are NOT committed to git for security. Create them manually:

```bash
# SSH to monitoring Talos node
ssh root@10.30.0.20

# Create namespace first (if not already created)
kubectl create namespace mcp-servers

# Create kubeconfig for production cluster
kubectl create configmap kubeconfig-prod \
  --from-file=kubeconfig=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig \
  -n mcp-servers

# Create talosconfig for production cluster
kubectl create configmap talosconfig \
  --from-file=talosconfig=/home/prod_homelab/infrastructure/terraform/generated/talosconfig \
  -n mcp-servers
```

**Note**: These ConfigMaps contain sensitive cluster credentials and should NEVER be committed to git.

## Deployment Steps

### 1. Commit MCP Server Manifests to Git

```bash
cd /home/monit_homelab

# Review what will be deployed
git status

# Should show:
# - kubernetes/platform/mcp-servers/
# - kubernetes/argocd-apps/platform/mcp-servers-app.yaml
# - .claude/skills/monitoring-ops/
# - .mcp.json

git add kubernetes/platform/mcp-servers/
git add kubernetes/argocd-apps/platform/mcp-servers-app.yaml
git add .claude/skills/monitoring-ops/
git add .mcp.json

git commit -m "Add MCP servers infrastructure with Infisical credentials

Deploy MCP servers for infrastructure management via Claude Code.

Components:
- Infisical MCP: Query secrets from prod-homelab-y-nij
- Coroot MCP: Observability queries for all clusters
- Proxmox MCP: Manage Ruapehu (prod) and Carrick (monitoring)
- Kubernetes MCP: Manage prod Talos and monitoring Talos clusters
- Talos MCP: Manage Talos OS nodes
- Network MCP: OPNsense, UniFi, AdGuard management

Architecture:
- All MCP servers deployed as K8s pods in mcp-servers namespace
- Credentials via InfisicalSecret (path /mcp-credentials)
- Exposed via NodePort 30080-30089
- Claude Code connects via HTTP

Skills:
- monitoring-ops: Default prompts for monitoring infrastructure
- .mcp.json: MCP server endpoint configuration

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push
```

Also commit to prod_homelab for Skills:

```bash
cd /home/prod_homelab

git add .claude/skills/infrastructure-ops/
git add .mcp.json

git commit -m "Add infrastructure-ops Skill and MCP configuration

Skills for production infrastructure management with default prompts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push
```

### 2. Deploy via ArgoCD

```bash
# Apply the ArgoCD application
kubectl apply -f /home/monit_homelab/kubernetes/argocd-apps/platform/mcp-servers-app.yaml

# Watch the sync
kubectl get application mcp-servers -n argocd -w

# Check pods
kubectl get pods -n mcp-servers
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
infisical-mcp-xxxxxxxxxx-xxxxx             1/1     Running   0          2m
coroot-mcp-xxxxxxxxxx-xxxxx                1/1     Running   0          2m
proxmox-ruapehu-mcp-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
proxmox-carrick-mcp-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
kubernetes-prod-mcp-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
kubernetes-monitoring-mcp-xxxxxxxxxx-xxxxx 1/1     Running   0          2m
talos-mcp-xxxxxxxxxx-xxxxx                 1/1     Running   0          2m
opnsense-mcp-xxxxxxxxxx-xxxxx              1/1     Running   0          2m
unifi-mcp-xxxxxxxxxx-xxxxx                 1/1     Running   0          2m
adguard-mcp-xxxxxxxxxx-xxxxx               1/1     Running   0          2m
```

### 3. Verify Deployments

```bash
# Check all services
kubectl get svc -n mcp-servers

# Should show NodePort services on 30080-30089

# Test connectivity to each MCP server
for port in {30080..30089}; do
  echo -n "Testing port $port: "
  timeout 2 curl -s http://10.30.0.20:$port > /dev/null && echo "OK" || echo "FAIL"
done
```

### 4. Check Logs (if issues)

```bash
# Check specific pod logs
kubectl logs -n mcp-servers deployment/infisical-mcp
kubectl logs -n mcp-servers deployment/coroot-mcp
kubectl logs -n mcp-servers deployment/proxmox-ruapehu-mcp

# Check InfisicalSecret sync status
kubectl get infisicalsecret -n mcp-servers
kubectl describe infisicalsecret mcp-credentials -n mcp-servers
```

## Verification

### 1. Test MCP Servers in Claude Code

From Claude Code in either repo:

```
# Test Infisical MCP
"Get list of secrets from /mcp-credentials path in Infisical"

# Test Coroot MCP
"Show me errors in the prod-homelab project from the last hour"

# Test Proxmox MCP
"List all VMs on Ruapehu"
"List all LXC containers on Carrick"

# Test Kubernetes MCP
"List all pods in argocd namespace on production cluster"
"Show all pods in monitoring namespace on Talos cluster"

# Test Talos MCP
"Check health of all Talos nodes"
"Show etcd cluster status"

# Test Network MCP
"Show current firewall rules on OPNsense"
"List all connected UniFi clients"
"Show top blocked domains on AdGuard"
```

### 2. Verify Skills are Active

Claude should automatically use the Skills when appropriate:

- Ask: "Check production cluster health" → Should activate `infrastructure-ops` Skill
- Ask: "Show Coroot errors" → Should activate `monitoring-ops` Skill

## Troubleshooting

### MCP Server Pod Failing

```bash
# Check pod status
kubectl describe pod -n mcp-servers <pod-name>

# Check logs
kubectl logs -n mcp-servers <pod-name>

# Common issues:
# 1. InfisicalSecret not synced → Check Infisical credentials
# 2. ConfigMap missing → Create kubeconfig/talosconfig ConfigMaps
# 3. Network connectivity → Check firewall rules, routing
```

### Infisical Credentials Not Loading

```bash
# Check InfisicalSecret status
kubectl get infisicalsecret mcp-credentials -n mcp-servers -o yaml

# Check if secret was created
kubectl get secret mcp-credentials -n mcp-servers

# Check Infisical operator logs
kubectl logs -n infisical-operator-system deployment/infisical-operator-controller-manager
```

### MCP Server Not Responding

```bash
# Test from monitoring cluster
ssh root@10.30.0.20
curl http://localhost:30080  # Test infisical-mcp

# Check service endpoints
kubectl get endpoints -n mcp-servers

# Restart deployment
kubectl rollout restart deployment/<mcp-server> -n mcp-servers
```

### ConfigMap Missing (kubeconfig/talosconfig)

These are manual because they contain sensitive credentials:

```bash
# Create from local files
kubectl create configmap kubeconfig-prod \
  --from-file=kubeconfig=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig \
  -n mcp-servers

kubectl create configmap talosconfig \
  --from-file=talosconfig=/home/prod_homelab/infrastructure/terraform/generated/talosconfig \
  -n mcp-servers
```

## MCP Server Endpoints

| Server | NodePort | Description |
|--------|----------|-------------|
| infisical-mcp | 30080 | Query secrets from Infisical |
| coroot-mcp | 30081 | Observability queries (logs, traces, metrics) |
| proxmox-ruapehu-mcp | 30082 | Manage production Proxmox (10.10.0.10) |
| proxmox-carrick-mcp | 30083 | Manage monitoring Proxmox (10.30.0.10) |
| kubernetes-prod-mcp | 30084 | Manage production Talos cluster |
| kubernetes-monitoring-mcp | 30085 | Manage monitoring Talos cluster |
| talos-mcp | 30086 | Manage Talos OS nodes |
| opnsense-mcp | 30087 | Manage OPNsense firewall |
| unifi-mcp | 30088 | Manage UniFi network |
| adguard-mcp | 30089 | Manage AdGuard DNS |

## Usage Examples

### Infisical MCP
```
"Get the value of CLOUDFLARE_API_TOKEN from Infisical"
"List all secrets in /kubernetes path"
"Show secret versions for CLOUDFLARE_TUNNEL_TOKEN"
```

### Coroot MCP
```
"Show CPU usage for homepage pod in last hour"
"Find slow requests to the homepage service"
"Analyze errors in argocd namespace"
"Show distributed traces for failed requests"
```

### Proxmox MCP
```
"List all VMs on Ruapehu and their resource usage"
"Show storage usage on Carrick"
"Check CPU allocation across all VMs"
"Show network interfaces on VM 450"
```

### Kubernetes MCP
```
"List failing pods in production cluster"
"Show ArgoCD application sync status"
"Get logs from homepage pod in last 10 minutes"
"Describe the coroot deployment in monitoring cluster"
```

### Talos MCP
```
"Check etcd cluster health"
"Show disk usage on talos-worker-1"
"Get kubelet logs from talos-worker-2"
"Show network configuration on all Talos nodes"
```

### Network MCP
```
OPNsense:
- "Show firewall rules for WAN interface"
- "List active VPN connections"
- "Show traffic statistics"

UniFi:
- "List all connected WiFi clients"
- "Show bandwidth usage on main switch"
- "List all SSIDs and their settings"

AdGuard:
- "Show top 10 blocked domains today"
- "List all DNS filtering rules"
- "Show query statistics for last 24 hours"
```

## Security Considerations

1. **Credentials in Infisical**: All API credentials stored in Infisical, not in git
2. **kubeconfig/talosconfig**: Manual ConfigMaps, NEVER committed to git
3. **Network isolation**: mcp-servers namespace isolated via NetworkPolicies
4. **RBAC**: kubernetes-monitoring-mcp uses view-only ServiceAccount
5. **Audit trail**: Infisical logs all secret access

## Monitoring MCP Servers

All MCP servers are automatically monitored by Coroot:

```bash
# Access Coroot UI
http://10.30.0.20:32702

# Select Project: monit-homelab
# View: mcp-servers namespace pods
# Check: CPU, memory, network, errors
```

## Updating MCP Servers

MCP servers are deployed via ArgoCD with auto-sync enabled:

```bash
# Update manifests in git
cd /home/monit_homelab
# Edit kubernetes/platform/mcp-servers/<server>/deployment.yaml

git add .
git commit -m "Update <server> MCP configuration"
git push

# ArgoCD auto-syncs within 3 minutes
# Or force sync:
kubectl patch application mcp-servers -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

## Next Steps

1. Explore Skills: Check `.claude/skills/*/SKILL.md` for default prompts
2. Test each MCP server with example queries
3. Monitor MCP server health via Coroot
4. Add more Skills for common workflows
5. Document your specific infrastructure queries

## Resources

- [MCP Specification](https://modelcontextprotocol.io/)
- [Infisical MCP Server](https://infisical.com/blog/managing-secrets-mcp-servers)
- [Coroot MCP Server](https://github.com/jamesbrink/mcp-coroot)
- [Proxmox MCP Server](https://github.com/gilby125/mcp-proxmox)
- [OPNsense MCP Server](https://github.com/Pixelworlds/opnsense-mcp-server)
- [UniFi MCP Server](https://github.com/sirkirby/unifi-network-mcp)
- [Talos MCP Server](https://github.com/5dlabs/talos-mcp)

---

**Last Updated**: 2025-12-21
**Deployed On**: Monitoring Talos Cluster (10.30.0.20)
**Managed By**: ArgoCD (GitOps)
