# ============================================================================
# Infisical Operator — MIGRATED TO ARGOCD
# ============================================================================
# The Infisical operator was originally bootstrapped here via Terraform to
# solve the chicken-and-egg problem (apps need secrets, secrets need operator).
#
# Now managed by ArgoCD (infisical-operator-monit application).
#
# For initial cluster bootstrap:
#   1. Create namespace: kubectl create ns infisical-operator-system
#   2. Create secret:    kubectl create secret generic universal-auth-credentials \
#        -n infisical-operator-system --from-literal=clientId=... --from-literal=clientSecret=...
#   3. Install helm:     helm install infisical-operator infisical/secrets-operator \
#        -n infisical-operator-system
#   4. Register with ArgoCD and let it take over.
# ============================================================================
