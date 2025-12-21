# Proxmox Connection (Carrick - Monitoring Host)
variable "monitoring_proxmox_host" {
  description = "Monitoring Proxmox host address (Carrick)"
  type        = string
  default     = "10.30.0.10"
}

variable "monitoring_proxmox_user" {
  description = "Proxmox API user"
  type        = string
  default     = "root@pam"
}

variable "monitoring_proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "monitoring_proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "Carrick"
}

# Network Configuration
variable "network_bridge" {
  description = "Management network bridge"
  type        = string
  default     = "vmbr0"
}

variable "monitoring_gateway" {
  description = "Monitoring network gateway"
  type        = string
  default     = "10.30.0.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
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
  description = "Proxmox storage pool for boot disk (Kerrier ZFS pool)"
  type        = string
  default     = "Kerrier"
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
    ip     = "10.30.0.20"
    cores  = 4
    memory = 12288 # 12GB - available on Carrick
    disk   = 50
  }
}

# Cilium LoadBalancer Configuration
variable "cilium_lb_ip_pool" {
  description = "IP pool for Cilium LoadBalancer"
  type = list(object({
    start = string
    stop  = string
  }))
  default = [
    {
      start = "10.30.0.90"
      stop  = "10.30.0.99"
    }
  ]
}
