# Environment Variables for Monitoring Homelab

This document details the environment variables required for deploying the K3s monitoring cluster on Proxmox Carrick.

## Quick Setup

```bash
# Create directory for credentials
mkdir -p ~/.config/terraform

# Create monitoring credentials file
cat > ~/.config/terraform/monitoring-creds.env << 'EOF'
# ============================================================================
# Monitoring Proxmox - Carrick (10.30.0.10)
# ============================================================================
export TF_VAR_monitoring_proxmox_host="https://10.30.0.10:8006"
export TF_VAR_monitoring_proxmox_user="root@pam"
export TF_VAR_monitoring_proxmox_password="H4ckwh1z"
export TF_VAR_monitoring_proxmox_node="Carrick"
export TF_VAR_monitoring_proxmox_storage="Kerrier"

# ============================================================================
# Production Proxmox - Ruapehu (10.10.0.10) [Reference Only]
# ============================================================================
# These are optional - only needed for cross-cluster operations
export TF_VAR_production_proxmox_host="https://10.10.0.10:8006"
export TF_VAR_production_proxmox_user="root@pam"
export TF_VAR_production_proxmox_password="your-production-password-here"
export TF_VAR_production_proxmox_node="Ruapehu"

# ============================================================================
# TrueNAS Configuration (10.30.0.120)
# ============================================================================
export TF_VAR_truenas_host="10.30.0.120"
export TF_VAR_truenas_api_key="your-truenas-api-key-here"
EOF

# Secure the file
chmod 600 ~/.config/terraform/monitoring-creds.env

# Source the variables
source ~/.config/terraform/monitoring-creds.env

# Verify variables are set
env | grep TF_VAR_monitoring
```

## Required Variables

### Monitoring Proxmox (Carrick)

| Variable | Value | Description |
|----------|-------|-------------|
| `TF_VAR_monitoring_proxmox_host` | `https://10.30.0.10:8006` | Carrick Proxmox API endpoint |
| `TF_VAR_monitoring_proxmox_user` | `root@pam` | Proxmox API user |
| `TF_VAR_monitoring_proxmox_password` | `H4ckwh1z` | Proxmox password (CHANGE IN PRODUCTION!) |
| `TF_VAR_monitoring_proxmox_node` | `Carrick` | Proxmox node name |
| `TF_VAR_monitoring_proxmox_storage` | `Kerrier` | ZFS storage pool for LXC |

## Optional Variables

### Production Proxmox (Ruapehu) - Reference Only

Only needed if you plan cross-cluster operations:

| Variable | Value | Description |
|----------|-------|-------------|
| `TF_VAR_production_proxmox_host` | `https://10.10.0.10:8006` | Ruapehu Proxmox API endpoint |
| `TF_VAR_production_proxmox_user` | `root@pam` | Proxmox API user |
| `TF_VAR_production_proxmox_password` | `your-password` | Proxmox password |
| `TF_VAR_production_proxmox_node` | `Ruapehu` | Proxmox node name |

### TrueNAS Configuration

Required for Phase 2 (monitoring stack) to scrape TrueNAS metrics:

| Variable | Value | Description |
|----------|-------|-------------|
| `TF_VAR_truenas_host` | `10.30.0.120` | TrueNAS IP address on Carrick |
| `TF_VAR_truenas_api_key` | `1-arHBVno...` | TrueNAS API key for metrics scraping |

**To get TrueNAS API key:**
1. Login to TrueNAS UI: http://10.30.0.120
2. Settings → API Keys
3. Click "Add" to create new key
4. Name: "Prometheus Monitoring"
5. Copy the generated key

### LXC Configuration Overrides

Override default LXC settings if needed:

```bash
export TF_VAR_lxc_vmid="200"
export TF_VAR_lxc_hostname="k3s-monitor"
export TF_VAR_lxc_ip="10.30.0.20/24"
export TF_VAR_lxc_cores="2"
export TF_VAR_lxc_memory="4096"
export TF_VAR_lxc_disk_size="30"
```

### K3s Configuration

```bash
# Specific K3s version (empty = latest)
export TF_VAR_k3s_version=""

# Components to disable (comma-separated)
export TF_VAR_k3s_disable_components='["traefik","servicelb","local-storage"]'
```

## Integration with Existing Credentials

If you already have production Proxmox credentials in `/home/.config/terraform/proxmox-creds.env`, you can merge them:

```bash
# Append monitoring variables to existing file
cat >> /home/.config/terraform/proxmox-creds.env << 'EOF'

# ============================================================================
# Monitoring Proxmox - Carrick (10.30.0.10)
# ============================================================================
export TF_VAR_monitoring_proxmox_host="https://10.30.0.10:8006"
export TF_VAR_monitoring_proxmox_user="root@pam"
export TF_VAR_monitoring_proxmox_password="H4ckwh1z"
export TF_VAR_monitoring_proxmox_node="Carrick"
export TF_VAR_monitoring_proxmox_storage="Kerrier"
EOF

# Source the combined file
source /home/.config/terraform/proxmox-creds.env
```

## Verification

After setting environment variables:

```bash
# Check monitoring variables
echo "Monitoring Host: $TF_VAR_monitoring_proxmox_host"
echo "Monitoring Node: $TF_VAR_monitoring_proxmox_node"
echo "Monitoring Storage: $TF_VAR_monitoring_proxmox_storage"

# List all Terraform variables
env | grep TF_VAR_ | sort

# Test Proxmox API access
curl -k "$TF_VAR_monitoring_proxmox_host/api2/json/version"
```

## Shell Integration

Add to your shell profile for persistence:

### Bash (~/.bashrc)

```bash
# Terraform Proxmox credentials
if [ -f ~/.config/terraform/monitoring-creds.env ]; then
    source ~/.config/terraform/monitoring-creds.env
fi
```

### Zsh (~/.zshrc)

```zsh
# Terraform Proxmox credentials
if [[ -f ~/.config/terraform/monitoring-creds.env ]]; then
    source ~/.config/terraform/monitoring-creds.env
fi
```

### Fish (~/.config/fish/config.fish)

```fish
# Terraform Proxmox credentials
if test -f ~/.config/terraform/monitoring-creds.env
    source ~/.config/terraform/monitoring-creds.env
end
```

## Security Best Practices

1. **Never commit** credentials to git
2. **Secure file permissions**: `chmod 600 ~/.config/terraform/monitoring-creds.env`
3. **Use strong passwords**: Change default passwords immediately
4. **Rotate credentials**: Update passwords periodically
5. **Limit access**: Only source credentials when needed
6. **Consider vault**: Use HashiCorp Vault or similar for production

## Troubleshooting

### Variables Not Set

```bash
# Check if file exists
ls -la ~/.config/terraform/monitoring-creds.env

# Source the file
source ~/.config/terraform/monitoring-creds.env

# Verify
echo $TF_VAR_monitoring_proxmox_host
```

### Permission Denied

```bash
# Fix permissions
chmod 600 ~/.config/terraform/monitoring-creds.env
```

### Terraform Can't Find Variables

```bash
# Ensure variables are exported
export TF_VAR_monitoring_proxmox_password="your-password"

# Or use terraform.tfvars instead
cd /home/monit_homelab/terraform/monitoring-lxc
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

## Alternative: terraform.tfvars

Instead of environment variables, you can use `terraform.tfvars`:

```bash
cd /home/monit_homelab/terraform/monitoring-lxc
cp terraform.tfvars.example terraform.tfvars

# Edit the file
nano terraform.tfvars
```

**Warning**: `terraform.tfvars` is gitignored to prevent credential leaks. Never commit this file!

## Reference

- [Terraform Environment Variables](https://www.terraform.io/docs/cli/config/environment-variables.html)
- [Proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- Production credentials location: `/home/.config/terraform/proxmox-creds.env`
