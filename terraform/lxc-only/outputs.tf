# ============================================================================
# Terraform Outputs - Connection Info for Ansible
# ============================================================================

output "lxc_id" {
  description = "LXC container ID (full resource ID)"
  value       = proxmox_virtual_environment_container.k3s_monitoring.id
}

output "lxc_vmid" {
  description = "LXC VM ID"
  value       = proxmox_virtual_environment_container.k3s_monitoring.vm_id
}

output "lxc_ip" {
  description = "LXC IP address (for Ansible inventory)"
  value       = trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")
}

output "lxc_hostname" {
  description = "LXC hostname"
  value       = var.lxc_hostname
}

output "ansible_inventory_snippet" {
  description = "Copy this to your Ansible inventory"
  value = <<-EOT
    k3s_monitor:
      ansible_host: ${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}
      ansible_user: root
      ansible_password: "{{ lookup('env', 'ANSIBLE_LXC_PASSWORD') }}"
  EOT
}

output "deployment_info" {
  description = "Deployment information and next steps"
  value       = <<-EOT
    ╔════════════════════════════════════════════════════════════════════╗
    ║  K3s Monitoring LXC - Infrastructure Deployment Complete           ║
    ╚════════════════════════════════════════════════════════════════════╝

    Container Details:
      VMID:     ${proxmox_virtual_environment_container.k3s_monitoring.vm_id}
      Hostname: ${var.lxc_hostname}
      IP:       ${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}
      Node:     ${var.monitoring_proxmox_node}
      Storage:  ${var.monitoring_proxmox_storage}

    Test SSH Connection (wait 30-60s for LXC to boot):
      ssh root@${trimprefix(trimsuffix(var.lxc_ip, "/24"), "/")}

    Next Steps:
      1. Configure LXC base:
         cd /home/monit_homelab/ansible
         source /home/monit_homelab/.env.monitoring
         ansible-playbook -i inventory/monitoring.yml playbooks/01-base-lxc.yml

      2. Install K3s:
         ansible-playbook -i inventory/monitoring.yml playbooks/02-k3s-install.yml

      3. Verify K3s:
         export KUBECONFIG=~/.kube/monitoring-k3s.yaml
         kubectl get nodes

    ╚════════════════════════════════════════════════════════════════════╝
  EOT
}
