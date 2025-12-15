# ============================================================================
# Production Proxmox Variables (Ruapehu) - Reference Only
# ============================================================================
# These variables reference the production Proxmox for potential cross-cluster
# operations. Set via TF_VAR_production_* environment variables.

variable "production_proxmox_host" {
  description = "Production Proxmox host URL (Ruapehu)"
  type        = string
  default     = "https://10.10.0.10:8006"
}

variable "production_proxmox_user" {
  description = "Production Proxmox API user"
  type        = string
  default     = "root@pam"
}

variable "production_proxmox_password" {
  description = "Production Proxmox password"
  type        = string
  sensitive   = true
}

variable "production_proxmox_node" {
  description = "Production Proxmox node name"
  type        = string
  default     = "Ruapehu"
}

# ============================================================================
# Monitoring Proxmox Variables (Carrick) - Active Deployment Target
# ============================================================================
# These variables configure the monitoring Proxmox where resources will be
# created. Set via TF_VAR_monitoring_* environment variables.

variable "monitoring_proxmox_host" {
  description = "Monitoring Proxmox host URL (Carrick)"
  type        = string
  default     = "https://10.30.0.10:8006"
}

variable "monitoring_proxmox_user" {
  description = "Monitoring Proxmox API user"
  type        = string
  default     = "root@pam"
}

variable "monitoring_proxmox_password" {
  description = "Monitoring Proxmox password"
  type        = string
  sensitive   = true
}

variable "monitoring_proxmox_node" {
  description = "Monitoring Proxmox node name"
  type        = string
  default     = "Carrick"
}

variable "monitoring_proxmox_storage" {
  description = "Storage pool for LXC container on Carrick"
  type        = string
  default     = "Kerrier" # ZFS pool discovered on Carrick
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "network_bridge" {
  description = "Network bridge for LXC container"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Network gateway for monitoring network"
  type        = string
  default     = "10.30.0.1"
}

variable "dns_servers" {
  description = "DNS servers for LXC container"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ============================================================================
# LXC Container Configuration
# ============================================================================

variable "lxc_vmid" {
  description = "LXC container ID"
  type        = number
  default     = 200
}

variable "lxc_hostname" {
  description = "LXC container hostname"
  type        = string
  default     = "k3s-monitor"
}

variable "lxc_ip" {
  description = "LXC container IP address (CIDR notation)"
  type        = string
  default     = "10.30.0.20/24"
}

variable "lxc_cores" {
  description = "Number of CPU cores for LXC container"
  type        = number
  default     = 2
}

variable "lxc_memory" {
  description = "Memory allocation in MB for LXC container"
  type        = number
  default     = 4096 # 4GB
}

variable "lxc_disk_size" {
  description = "Disk size in GB for LXC container"
  type        = number
  default     = 30
}

variable "lxc_template" {
  description = "LXC template path on Proxmox"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-1_amd64.tar.zst"
}

# ============================================================================
# K3s Configuration
# ============================================================================

variable "k3s_version" {
  description = "K3s version to install (leave empty for latest stable)"
  type        = string
  default     = "" # Empty string installs latest stable
}

variable "k3s_disable_components" {
  description = "K3s components to disable"
  type        = list(string)
  default     = ["traefik", "servicelb", "local-storage"]
}

# ============================================================================
# SSH Configuration
# ============================================================================

variable "ssh_public_key" {
  description = "SSH public key for LXC access"
  type        = string
  default     = "" # Will use root password if empty
}

variable "root_password" {
  description = "Root password for LXC container"
  type        = string
  sensitive   = true
  default     = "" # Set via environment variable or terraform.tfvars
}
