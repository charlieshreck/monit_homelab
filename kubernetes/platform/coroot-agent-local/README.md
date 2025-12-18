# Coroot Monitoring Cluster Agents

Deploys Coroot cluster-agent ONLY to monitoring cluster (no node-agent due to memory constraints).

## Components

- **Cluster Agent**: 1 replica Deployment for K8s resource discovery
- **Node Agent**: DISABLED (memory pressure on single-node cluster)

## Rationale

Monitoring cluster has ~2GB available after all workloads:
- Node-agent would consume ~256Mi-1Gi
- Not critical for monitoring infrastructure
- Cluster-agent provides sufficient K8s resource discovery

## Prerequisites

API key must exist in Infisical:
- Project: `prod_homelab` (slug: `prod-homelab-y-nij`)
- Environment: `prod`
- Path: `/monitoring/coroot`
- Key: `monit_apikey` (extracted from monit-homelab-api-key secret after Coroot server deployment)

## Configuration

- **Coroot Server URL**: `http://coroot-coroot.coroot.svc.cluster.local:8080` (in-cluster service)
- **API Key**: Synced from Infisical (`monit_apikey`)
- **Cluster Name**: `monit-homelab`

## RBAC

- ServiceAccount: `coroot-cluster-agent`
- ClusterRole: `coroot-cluster-agent-local`
- ClusterRoleBinding: **Correct namespace: coroot-agent**

## Pod Security

- Namespace: `baseline` (not privileged, no eBPF)
- No host mounts needed (cluster-agent only)

## Deployment

Managed by ArgoCD application: `coroot-agent-local` (sync-wave: 3)
- Deploys to monitoring cluster (`https://10.30.0.20:6443`)
- Creates namespace: `coroot-agent`
- Syncs API key from Infisical every 60 seconds
