# ============================================================================
# Terraform Outputs - K3s Monitoring Cluster
# ============================================================================

# Cluster Information
output "cluster_name" {
  description = "K3s cluster identifier"
  value       = "monitoring-k3s"
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}:6443"
}

# Container Information
output "lxc_vmid" {
  description = "LXC container ID in Proxmox"
  value       = proxmox_virtual_environment_container.k3s_monitoring.vm_id
}

output "lxc_ip" {
  description = "LXC container IP address"
  value       = trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")
}

output "lxc_hostname" {
  description = "LXC container hostname"
  value       = var.lxc_hostname
}

# Proxmox Information
output "proxmox_node" {
  description = "Proxmox node hosting the container"
  value       = var.monitoring_proxmox_node
}

output "proxmox_host" {
  description = "Proxmox host URL"
  value       = var.monitoring_proxmox_host
}

# Kubeconfig
output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = "~/.kube/monitoring-k3s.yaml"
}

output "kubeconfig_export_command" {
  description = "Command to set KUBECONFIG environment variable"
  value       = "export KUBECONFIG=~/.kube/monitoring-k3s.yaml"
}

# Access Commands
output "ssh_command" {
  description = "SSH command to access the LXC container"
  value       = "ssh root@${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}"
}

output "kubectl_test_command" {
  description = "Command to test kubectl access"
  value       = "KUBECONFIG=~/.kube/monitoring-k3s.yaml kubectl get nodes"
}

# K3s Configuration
output "k3s_version" {
  description = "K3s version installed (empty = latest stable)"
  value       = var.k3s_version != "" ? var.k3s_version : "latest stable"
}

output "k3s_disabled_components" {
  description = "Disabled K3s components"
  value       = var.k3s_disable_components
}

# Network Information
output "network_info" {
  description = "Network configuration summary"
  value = {
    ip      = trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")
    subnet  = "10.30.0.0/24"
    gateway = var.gateway
    bridge  = var.network_bridge
    dns     = var.dns_servers
  }
}

# Quick Start Guide
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ╔══════════════════════════════════════════════════════════════════════════╗
    ║  K3s Monitoring Cluster - Deployment Complete!                          ║
    ╚══════════════════════════════════════════════════════════════════════════╝

    📋 Cluster Information:
       Node:     ${var.lxc_hostname}
       IP:       ${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}
       API:      https://${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}:6443
       VMID:     ${var.lxc_vmid}

    🔑 Access the Cluster:
       1. Export kubeconfig:
          export KUBECONFIG=~/.kube/monitoring-k3s.yaml

       2. Verify cluster:
          kubectl get nodes
          kubectl get pods -A

       3. SSH to container:
          ssh root@${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}

    📦 Next Steps:
       1. Install monitoring stack (Prometheus, Grafana, etc.)
       2. Configure ingress controller (if needed)
       3. Setup persistent storage (if needed)
       4. Configure monitoring targets

    📖 Documentation:
       - K3s docs: https://docs.k3s.io
       - Kubeconfig: ~/.kube/monitoring-k3s.yaml
       - Terraform state: ${path.module}/terraform.tfstate

    ⚠️  Notes:
       - Disabled components: ${join(", ", var.k3s_disable_components)}
       - Network isolated from production (10.30.0.0/24 vs 10.10.0.0/24)
       - Single-node cluster (no HA)
  EOT
}
