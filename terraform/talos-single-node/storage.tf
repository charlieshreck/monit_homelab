# ============================================================================
# Storage — MIGRATED TO ARGOCD
# ============================================================================
# Local-path-provisioner, NFS PVs/PVCs, namespaces, and storage classes were
# originally bootstrapped here. Now all managed by ArgoCD:
#   - local-path-provisioner-monit (ArgoCD app)
#   - victoria-metrics / victoria-logs helm releases create their own PVCs
#   - Namespaces created by ArgoCD apps (monitoring, coroot, local-path-storage)
#
# For initial cluster bootstrap, create NFS PVs and namespaces manually,
# then register with ArgoCD.
#
# NFS storage paths (TrueNAS-HDD Tekapo pool via 10.30.0.103):
#   - /mnt/Tekapo/victoria-metrics (500Gi)
#   - /mnt/Tekapo/victoria-logs (1000Gi)
# ============================================================================
