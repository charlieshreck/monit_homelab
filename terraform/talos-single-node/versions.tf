terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    # NOTE: helm, kubectl, kubernetes, infisical providers removed.
    # All K8s resources now managed by ArgoCD. See bootstrap notes in
    # cilium.tf, infisical.tf, storage.tf.
  }
}
