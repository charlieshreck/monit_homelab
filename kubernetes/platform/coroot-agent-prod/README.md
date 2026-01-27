# Coroot Production Cluster Agents

Deploys Coroot agents (cluster-agent and node-agent) to production cluster.

## Components

- **Cluster Agent**: 1 replica Deployment for K8s resource discovery
- **Node Agents**: DaemonSet on all workers (eBPF for traces, profiles, logs)

## Prerequisites

API key must exist in Infisical:
- Project: `prod_homelab` (slug: `prod-homelab-y-nij`)
- Environment: `prod`
- Path: `/monitoring/coroot`
- Key: `application_apikey` (extracted from prod-homelab-api-key secret after Coroot server deployment)

## Configuration

- **Coroot Server URL**: `http://coroot.monit.kernow.io` (Traefik ingress on monitoring cluster)
- **API Key**: Synced from Infisical (`application_apikey`)
- **Cluster Name**: `prod-homelab`

## RBAC

- ServiceAccount: `coroot-cluster-agent`
- ClusterRole: `coroot-cluster-agent`
- ClusterRoleBinding: **FIXED namespace to coroot-agent** (was causing 404 errors)

## eBPF Requirements

Node agents require:
- Talos kernel with eBPF support (default v1.3+)
- Privileged pod security (namespace labels)
- Host mounts: `/sys`, `/proc`, `/sys/kernel/debug`

## Deployment

Managed by ArgoCD application: `coroot-agent-prod` (sync-wave: 3)
- Deploys to production cluster (`https://kubernetes.default.svc`)
- Creates namespace: `coroot-agent`
- Syncs API key from Infisical every 60 seconds
