#!/bin/bash
set -e

MONIT_KUBECONFIG="/home/monit_homelab/terraform/talos-single-node/generated/kubeconfig"
PROD_KUBECONFIG="/home/prod_homelab/infrastructure/terraform/generated/kubeconfig"

echo "=== Syncing Coroot API Keys ==="

# Wait for operator to generate API keys
echo "Waiting for Coroot operator to generate API keys..."
sleep 30

# Extract API keys from monitoring cluster
export KUBECONFIG="$MONIT_KUBECONFIG"

PROD_KEY=$(kubectl get secret prod-homelab-api-key -n coroot -o jsonpath='{.data.apikey}' | base64 -d)
MONIT_KEY=$(kubectl get secret monit-homelab-api-key -n coroot -o jsonpath='{.data.apikey}' | base64 -d)

echo "✓ Extracted API keys from Coroot server"

# Update agent secret on production cluster
# Format required by coroot-ce Helm chart: key name must be "apiKey"
export KUBECONFIG="$PROD_KUBECONFIG"

kubectl create secret generic coroot-agent-apikey -n coroot-agent \
  --from-literal=apiKey="$PROD_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Updated production cluster agent API key"

# Restart production agents if they exist
kubectl rollout restart deployment -l app.kubernetes.io/name=coroot-ce -n coroot-agent 2>/dev/null || true
kubectl rollout restart daemonset -l app.kubernetes.io/name=coroot-ce -n coroot-agent 2>/dev/null || true

echo "✓ Production agents restarted"
echo ""
echo "=== API Key Sync Complete ==="
echo "Access Coroot UI: http://10.30.0.20:32702 (NodePort)"
