# GitOps Workflow - MANDATORY FOR ALL CHANGES

## CRITICAL RULE: Infrastructure as Code (IaC) ONLY

**ALWAYS follow this workflow. NO EXCEPTIONS.**

This repository uses GitOps principles. ALL infrastructure changes MUST be:
1. Defined in code (Terraform, Kubernetes manifests)
2. Committed to git
3. Deployed via automation (Terraform, ArgoCD)

## Deployment Methods by Component

| Component | Tool | Workflow |
|-----------|------|----------|
| **Talos VM** | Terraform | `terraform plan` → `terraform apply` |
| **Kubernetes Resources** | ArgoCD | Commit to git → ArgoCD auto-sync (from prod cluster) |
| **Secrets** | Infisical | Add to Infisical → InfisicalSecret CR in K8s |

## The ONLY Correct Workflow

### For Terraform (Talos VM on Pihanga)

```bash
cd /home/monit_homelab/terraform/talos-single-node

# 1. Make changes to .tf files
vim main.tf

# 2. Commit to git FIRST
git add .
git commit -m "Description of change"
git push

# 3. Plan
terraform plan -out=monitoring.plan

# 4. Review plan output carefully

# 5. Apply
terraform apply monitoring.plan

# 6. Export kubeconfig if cluster changed
export KUBECONFIG=/home/monit_homelab/kubeconfig
```

### For Kubernetes (Monitoring stack)

```bash
cd /home/monit_homelab

# 1. Make changes to manifests
vim kubernetes/platform/beszel/deployment.yaml

# 2. Commit to git FIRST (this is the deployment!)
git add .
git commit -m "Description of change"
git push

# 3. ArgoCD (on prod cluster) automatically syncs within 3 minutes
# OR force sync from prod cluster:
kubectl --kubeconfig $KUBECONFIG_PROD patch application <app> -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# 4. Verify (on monit cluster)
export KUBECONFIG=$KUBECONFIG_MONIT
kubectl get pods -n monitoring
```

### For Secrets

```bash
# 1. Add secret to Infisical
#    Project: prod_homelab (slug: prod-homelab-y-nij)
#    Environment: prod
#    Path: /observability/<service>

# 2. Create InfisicalSecret CR manifest
vim kubernetes/platform/infisical-credentials.yaml

# 3. Commit to git
git add .
git commit -m "Add InfisicalSecret for credentials"
git push

# 4. ArgoCD auto-syncs
# Secret appears in K8s automatically

# 5. Verify
kubectl get infisicalsecret -n monitoring
kubectl get secret <name> -n monitoring
```

## FORBIDDEN Actions

### NEVER DO THESE:

```bash
# WRONG: Manual kubectl apply
kubectl apply -f deployment.yaml

# WRONG: Manual kubectl edit
kubectl edit deployment grafana

# WRONG: Manual kubectl create
kubectl create secret generic my-secret

# WRONG: Direct terraform apply without git commit
terraform apply

# WRONG: Hardcoded secrets in manifests
echo "password: mypassword" > secret.yaml

# WRONG: SSH to the node (Talos has no SSH)
ssh root@10.10.0.30
```

### CORRECT Alternatives:

```bash
# RIGHT: Commit to git, let ArgoCD sync
git add . && git commit -m "Update deployment" && git push

# RIGHT: Update manifest in git
vim kubernetes/platform/beszel/deployment.yaml
git add . && git commit && git push

# RIGHT: Use InfisicalSecret CR
# Add to Infisical, create InfisicalSecret manifest, commit

# RIGHT: Commit terraform changes first
git add . && git commit && git push
terraform plan && terraform apply

# RIGHT: Use talosctl for node operations
talosctl --nodes 10.10.0.30 health
```

## Exception: Manual ConfigMaps for Sensitive Configs

**ONLY for files that cannot be in git** (kubeconfig, talosconfig from prod cluster):

```bash
# These are NOT committed to git (security)
# Document these in README.md files

kubectl create configmap kubeconfig-prod \
  --from-file=kubeconfig=/home/prod_homelab/infrastructure/terraform/generated/kubeconfig \
  -n monitoring

kubectl create configmap talosconfig \
  --from-file=talosconfig=/home/prod_homelab/infrastructure/terraform/generated/talosconfig \
  -n monitoring
```

**Always document manual ConfigMaps in README.md** so they can be recreated after cluster rebuild.

## GitOps Principles

1. **Git is the source of truth**
   - All infrastructure defined in git
   - No manual changes outside git
   - Git history = audit trail

2. **Declarative configuration**
   - Define desired state, not steps
   - Tools reconcile actual state to desired state
   - Idempotent operations

3. **Automated deployment**
   - ArgoCD (on prod cluster) watches this git repo
   - Automatically applies changes to monitoring cluster
   - Self-healing (reverts manual changes)

4. **No kubectl apply**
   - ArgoCD handles all K8s deployments
   - Manual kubectl only for debugging/verification
   - Read-only kubectl commands are fine

## Workflow Checklist

Before making ANY infrastructure change:

- [ ] Is the change defined in code? (Terraform/K8s manifest)
- [ ] Have I committed to git?
- [ ] Have I pushed to GitHub?
- [ ] Am I using the correct tool? (Terraform/ArgoCD)
- [ ] Am I avoiding manual kubectl apply?
- [ ] Are secrets in Infisical, not hardcoded?

If you answered NO to any question, STOP and follow the correct workflow.

## Emergency: Reverting Changes

```bash
# Kubernetes (via ArgoCD)
git revert <commit-hash>
git push
# ArgoCD auto-syncs the revert

# Terraform
git revert <commit-hash>
git push
terraform plan  # Verify revert
terraform apply
```

## Why GitOps?

1. **Audit trail**: Every change tracked in git history
2. **Rollback**: Easy to revert via git
3. **Consistency**: Same process for all changes
4. **Disaster recovery**: Entire infrastructure in git
5. **No drift**: ArgoCD enforces desired state

## Monitoring Cluster Specifics

- **Talos Linux**: Single-node VM on Proxmox Pihanga (10.10.0.20), node IP 10.10.0.30
- **Kubernetes**: v1.34.1 with Cilium CNI
- **Purpose**: Monitoring infrastructure (Coroot, VictoriaMetrics, Grafana, etc.)
- **Storage**: NFS from TrueNAS-HDD (10.10.0.103) + Cilium LB (10.10.0.31-35)
- **ArgoCD**: Managed remotely from prod cluster

---

**Remember**: If it's not in git, it doesn't exist. If you didn't commit first, you did it wrong.
