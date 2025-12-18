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

# Update agent secret on monitoring cluster
kubectl create secret generic coroot-api-key -n coroot-agent \
  --from-literal=apikey="$MONIT_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Updated monitoring cluster agent API key"

# Update agent secret on production cluster
export KUBECONFIG="$PROD_KUBECONFIG"

kubectl create secret generic coroot-api-key -n coroot-agent \
  --from-literal=apikey="$PROD_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Updated production cluster agent API key"

# Restart agents to pick up new keys
kubectl rollout restart deployment/coroot-cluster-agent -n coroot-agent
kubectl rollout restart daemonset/coroot-node-agent -n coroot-agent

export KUBECONFIG="$MONIT_KUBECONFIG"
kubectl rollout restart deployment/coroot-cluster-agent -n coroot-agent
kubectl rollout restart daemonset/coroot-node-agent -n coroot-agent

echo "✓ Restarted agents on both clusters"
echo ""
echo "=== API Key Sync Complete ==="
echo "Access Coroot UI: http://10.30.0.90:8080"
