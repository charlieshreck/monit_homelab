# ============================================================================
# Infisical Operator - Bootstrap via Terraform
# ============================================================================
# CRITICAL: Deploy Infisical operator BEFORE ArgoCD registration
# This solves the chicken-and-egg problem: apps need secrets, secrets need operator
# ============================================================================

# Create infisical-operator-system namespace
resource "kubernetes_namespace" "infisical_operator" {
  metadata {
    name = "infisical-operator-system"
  }

  depends_on = [
    data.talos_cluster_health.this,
  ]
}

# Create universal-auth-credentials secret
resource "kubernetes_secret" "infisical_universal_auth" {
  metadata {
    name      = "universal-auth-credentials"
    namespace = kubernetes_namespace.infisical_operator.metadata[0].name
  }

  type = "Opaque"

  data = {
    clientId     = "MGI4NWExYzctYTNiOS00Zjk3LThiMDgtYmFjZjc3MWRjMWM4"  # Base64: 0b85a1c7-a3b9-4f97-8b08-bacf771dc1c8
    clientSecret = "NjgyNzU0NGY5OTMyOWRjNGRmOTk3NTMwNDJjOTM3MWExMThkMmJmMWE5NzI2ODY5MTY1OWRkZDA4MDhjYmQzYQ=="  # Base64: 6827544f99329dc4df99753042c9371a118d2bf1a97268691659ddd0808cbd3a
  }
}

# Deploy Infisical operator via Helm
resource "helm_release" "infisical_operator" {
  name       = "infisical-operator"
  repository = "https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/"
  chart      = "secrets-operator"
  version    = "0.10.2"
  namespace  = kubernetes_namespace.infisical_operator.metadata[0].name

  depends_on = [
    kubernetes_secret.infisical_universal_auth,
  ]
}
