# Coroot Production Cluster Agents

Deploys Coroot agents (cluster-agent and node-agent) to the production cluster using the agents-only mode.

## Prerequisites

1. **Add API key to Infisical**:
   - Log into Infisical: https://app.infisical.com
   - Project: `prod_homelab` (slug: `prod-homelab-y-nij`)
   - Environment: `prod`
   - Path: `/monitoring/coroot`
   - Add secrets:
     - Key: `application_apikey`
     - Value: `QJBfFLGIEXAQ8XboNJdXLj07D8IhcPzJ`
     - (Extract from monitoring cluster: `kubectl get secret prod-homelab-api-key -n coroot -o jsonpath='{.data.apikey}' | base64 -d`)

2. **Verify InfisicalSecret**:
   ```bash
   kubectl get infisicalsecret -n coroot-agent
   kubectl get secret coroot-agent-apikey -n coroot-agent
   ```

## Configuration

- **Coroot Server URL**: `http://10.30.0.20:32702` (NodePort)
- **API Key**: Synced from Infisical (`/monitoring/coroot/application_apikey`)
- **Agents**: cluster-agent (1 replica) + node-agent (DaemonSet on all workers)

## Deployment

Managed by ArgoCD application: `coroot-agent-prod`
- Manual Kubernetes manifests (cluster-agent Deployment + node-agent DaemonSet)
- Secret: InfisicalSecret pulls API key from Infisical
- Sync wave: 4 (after server and config)

Note: Using manual manifests instead of Helm chart because the coroot-ce chart
creates a Coroot CR even in agents-only mode, requiring the operator to be present.
The operator is only on the monitoring cluster.
