# ============================================================================
# Cilium CNI — MIGRATED TO ARGOCD
# ============================================================================
# Cilium was originally bootstrapped here via Terraform, but is now managed
# exclusively by ArgoCD (monit_homelab/kubernetes/argocd-apps/platform/).
#
# For initial cluster bootstrap, install Cilium manually:
#   export KUBECONFIG=./generated/kubeconfig
#   helm install cilium cilium/cilium --version 1.19.1 --namespace kube-system \
#     --set kubeProxyReplacement=true --set k8sServiceHost=10.10.0.30 ...
#
# Then register the cluster with prod ArgoCD and let it take over.
# ============================================================================

# Output retained for reference
output "cilium_status" {
  description = "Cilium CNI installation status"
  value       = "Cilium managed by ArgoCD (IP pool: ${join(", ", [for block in var.cilium_lb_ip_pool : "${block.start}-${block.stop}"])})"
}
