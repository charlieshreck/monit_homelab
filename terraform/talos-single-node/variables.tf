# Proxmox Connection (Pihanga - Monitoring + Backup Host)
variable "monitoring_proxmox_host" {
  description = "Monitoring Proxmox host address (Pihanga)"
  type        = string
  default     = "10.10.0.20"
}

variable "monitoring_proxmox_token_id" {
  description = "Proxmox API token ID (e.g., root@pam!terraform)"
  type        = string
  sensitive   = true
}

variable "monitoring_proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "monitoring_proxmox_ssh_password" {
  description = "Proxmox SSH password (for ISO uploads)"
  type        = string
  sensitive   = true
}

variable "monitoring_proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "Pihanga"
}

# Network Configuration
variable "network_bridge" {
  description = "Management network bridge"
  type        = string
  default     = "vmbr0"
}

variable "monitoring_gateway" {
  description = "Monitoring network gateway (prod network temporarily)"
  type        = string
  default     = "10.10.0.1"
}

variable "dns_servers" {
  description = "DNS servers (local DNS stack for internal resolution, public fallback)"
  type        = list(string)
  default     = ["10.10.0.1", "9.9.9.9"]
}

# Cluster Configuration
variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "monitoring-cluster"
}

variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "v1.11.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.34.1"
}

# Storage Configuration
variable "monitoring_proxmox_storage" {
  description = "Proxmox storage pool for boot disk (Mauao ZFS pool on Pihanga)"
  type        = string
  default     = "Mauao"
}

variable "proxmox_iso_storage" {
  description = "Proxmox storage for ISO images"
  type        = string
  default     = "local"
}

# Single Node Configuration
variable "monitoring_node" {
  description = "Monitoring node VM configuration"
  type = object({
    vmid   = number
    name   = string
    ip     = string
    cores  = number
    memory = number
    disk   = number
  })
  default = {
    vmid   = 200
    name   = "talos-monitor"
    ip     = "10.10.0.30"
    cores  = 6          # Pihanga has 6C/12T
    memory = 20480      # 20GB - Pihanga has 28GB total
    disk   = 50
  }
}

# Infisical Operator Credentials
variable "infisical_client_id" {
  description = "Infisical universal auth client ID"
  type        = string
  sensitive   = true
}

variable "infisical_client_secret" {
  description = "Infisical universal auth client secret"
  type        = string
  sensitive   = true
}

# Cilium LoadBalancer Configuration
variable "cilium_lb_ip_pool" {
  description = "IP pool for Cilium LoadBalancer (prod network - verified free range)"
  type = list(object({
    start = string
    stop  = string
  }))
  default = [
    {
      start = "10.10.0.31"
      stop  = "10.10.0.35"
    }
  ]
}
