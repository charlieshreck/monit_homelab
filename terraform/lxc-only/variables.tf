# ============================================================================
# Monitoring Proxmox Variables (Carrick)
# ============================================================================

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
  description = "Storage pool for LXC container"
  type        = string
  default     = "Kerrier"
}

# ============================================================================
# Production Proxmox Variables (Optional - for reference)
# ============================================================================

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
  default     = ""
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "10.30.0.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ============================================================================
# LXC Configuration
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
  description = "LXC container IP (CIDR notation)"
  type        = string
  default     = "10.30.0.20/24"
}

variable "lxc_cores" {
  description = "CPU cores"
  type        = number
  default     = 2
}

variable "lxc_memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "lxc_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 30
}

variable "lxc_template" {
  description = "LXC template"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-1_amd64.tar.zst"
}

variable "lxc_root_password" {
  description = "Root password for LXC (used by Ansible)"
  type        = string
  sensitive   = true
}
