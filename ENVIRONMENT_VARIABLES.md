# Environment Variables for Monitoring Homelab

This document details the environment variables required for deploying the Talos Linux monitoring cluster on Proxmox Carrick.

## Quick Setup

```bash
# Source variables are typically managed via Infisical or terraform.tfvars
# See terraform/talos-single-node/terraform.tfvars for active configuration

cd /home/monit_homelab/terraform/talos-single-node
```

## Required Variables

### Monitoring Proxmox (Carrick)

| Variable | Value | Description |
|----------|-------|-------------|
| `monitoring_proxmox_host` | `10.30.0.10` | Carrick Proxmox host address |
| `monitoring_proxmox_user` | `root@pam` | Proxmox API user |
| `monitoring_proxmox_password` | (secret) | Proxmox password (in Infisical) |
| `monitoring_proxmox_node` | `Carrick` | Proxmox node name |
| `monitoring_proxmox_storage` | `Kerrier` | ZFS storage pool for VM boot disk |

### Cluster Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `monitoring-cluster` | Kubernetes cluster name |
| `talos_version` | `v1.11.5` | Talos Linux version |
| `kubernetes_version` | `v1.34.1` | Kubernetes version |

### Node Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `monitoring_node.vmid` | `200` | VM ID on Proxmox |
| `monitoring_node.name` | `talos-monitor` | VM hostname |
| `monitoring_node.ip` | `10.30.0.20` | Node IP address |
| `monitoring_node.cores` | `4` | CPU cores |
| `monitoring_node.memory` | `12288` | RAM in MB (12GB) |
| `monitoring_node.disk` | `50` | Boot disk in GB |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `network_bridge` | `vmbr0` | Management network bridge |
| `monitoring_gateway` | `10.30.0.1` | Network gateway |
| `dns_servers` | `["1.1.1.1", "8.8.8.8"]` | DNS servers |
| `cilium_lb_ip_pool` | `10.30.0.90-99` | Cilium LoadBalancer IP range |

## Setting Variables

### Option 1: terraform.tfvars (Preferred)

```bash
cd /home/monit_homelab/terraform/talos-single-node
# terraform.tfvars already exists and is gitignored
# Edit to update sensitive values
```

### Option 2: Environment Variables

```bash
export TF_VAR_monitoring_proxmox_password="your-password"
```

### Option 3: Infisical (Production)

Secrets are managed via Infisical at path `/infrastructure/proxmox-carrick/`.

```bash
# Retrieve via CLI
/root/.config/infisical/secrets.sh get /infrastructure/proxmox-carrick PASSWORD
```

## Verification

```bash
cd /home/monit_homelab/terraform/talos-single-node

# Validate configuration
terraform validate

# Plan (will show if variables are missing)
terraform plan
```

## Security Best Practices

1. **Never commit** `terraform.tfvars` to git (already gitignored)
2. **Use Infisical** for secret management in production
3. **Rotate credentials** periodically
4. **Limit access** - only the iac LXC needs these credentials

## Reference

- **Terraform Variables**: `terraform/talos-single-node/variables.tf`
- **Infisical Path**: `/infrastructure/proxmox-carrick/`
- **Proxmox Provider**: https://registry.terraform.io/providers/bpg/proxmox
- **Talos Provider**: https://registry.terraform.io/providers/siderolabs/talos
