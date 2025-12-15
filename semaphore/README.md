# Ansible Semaphore Installation Guide

Ansible Semaphore provides a modern web UI for managing and executing Ansible playbooks without requiring SSH/terminal access.

## Architecture

- **Location**: iac LXC (10.10.0.175)
- **Database**: SQLite (simple, no external dependencies)
- **Port**: 3000 (default)
- **Access**: http://10.10.0.175:3000

## Installation Steps

### 1. Download Semaphore Binary

```bash
# Get latest version (check https://github.com/semaphoreui/semaphore/releases)
SEMAPHORE_VERSION="v2.16.0"
wget -O /tmp/semaphore.tar.gz \
  "https://github.com/semaphoreui/semaphore/releases/download/${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.tar.gz"

# Extract
sudo tar -xzf /tmp/semaphore.tar.gz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/semaphore

# Verify
semaphore version
```

### 2. Create Semaphore User and Directories

```bash
# Create dedicated user
sudo useradd -r -s /bin/false -d /var/lib/semaphore semaphore

# Create directories
sudo mkdir -p /etc/semaphore
sudo mkdir -p /var/lib/semaphore
sudo chown -R semaphore:semaphore /var/lib/semaphore
```

### 3. Configure Semaphore

Run interactive setup:
```bash
cd /etc/semaphore
sudo semaphore setup
```

**Configuration choices:**
- Database: `3` (SQLite)
- Database path: `/var/lib/semaphore/semaphore.db`
- Admin username: `chaz`
- Admin email: `chaz@localhost`
- Admin name: `Chaz`
- Admin password: `H4ckwh1z`
- Playbook path: `/home/monit_homelab/ansible`
- Web host: `0.0.0.0` (listen on all interfaces)
- Web port: `3000`
- Enable email alerts: `no` (for now)
- Enable Telegram alerts: `no` (for now)
- Enable Slack alerts: `no` (for now)

This creates `/etc/semaphore/config.json`.

### 4. Create Systemd Service

Create `/etc/systemd/system/semaphore.service`:

```ini
[Unit]
Description=Ansible Semaphore
Documentation=https://docs.semaphoreui.com
After=network.target

[Service]
Type=simple
User=semaphore
Group=semaphore
ExecStart=/usr/local/bin/semaphore server --config /etc/semaphore/config.json
WorkingDirectory=/var/lib/semaphore
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/semaphore

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable semaphore
sudo systemctl start semaphore
sudo systemctl status semaphore
```

### 5. Fix Permissions for Ansible Playbooks

Semaphore needs read access to the Ansible directory:
```bash
sudo chmod -R o+rX /home/monit_homelab/ansible
```

### 6. Access Web UI

Open your browser to: **http://10.10.0.175:3000**

**Login credentials:**
- Username: `chaz`
- Password: `H4ckwh1z`

---

## Semaphore Configuration (Web UI)

### Step 1: Create Key Store (SSH Access)

1. Navigate to: **Key Store**
2. Click **"New Key"**
3. Configure:
   - **Name**: `k3s-monitor-root`
   - **Type**: `Login with password`
   - **Username**: `root`
   - **Password**: (your LXC root password)
4. Click **Create**

### Step 2: Create Inventory

1. Navigate to: **Inventory**
2. Click **"New Inventory"**
3. Configure:
   - **Name**: `Monitoring K3s`
   - **Inventory Type**: `Static YAML`
   - **SSH Key**: Select `k3s-monitor-root`
4. **Inventory** content - paste this:
   ```yaml
   all:
     hosts:
       k3s_monitor:
         ansible_host: 10.30.0.20
         ansible_user: root
         ansible_python_interpreter: /usr/bin/python3
         ansible_ssh_common_args: '-o StrictHostKeyChecking=no'

     vars:
       monitoring_network: 10.30.0.0/24
       k3s_cluster_cidr: 10.42.0.0/16
       k3s_service_cidr: 10.43.0.0/16
       k3s_version: stable
       k3s_server_ip: 10.30.0.20
       k3s_disable_components: [traefik, servicelb, local-storage]
       k3s_flannel_backend: host-gw
       kubeconfig_dest: ~/.kube/monitoring-k3s.yaml
   ```
5. Click **Create**

**Note**: This inventory doesn't use password lookup since Semaphore handles credentials via Key Store.

### Step 3: Create Environment

1. Navigate to: **Environment**
2. Click **"New Environment"**
3. Configure:
   - **Name**: `Monitoring Production`
   - **Variables** (JSON) - optional for now:
   ```json
   {
     "KUBECONFIG": "~/.kube/monitoring-k3s.yaml"
   }
   ```
4. Click **Create**

### Step 4: Create Playbook Repository

1. Navigate to: **Repositories**
2. Click **"New Repository"**
3. Configure:
   - **Name**: `monit_homelab`
   - **URL/Path**: `/home/monit_homelab/ansible`
   - **Branch**: (leave empty for local filesystem)
   - **SSH Key**: None (local access)
4. Click **Create**

### Step 5: Create Task Templates

Create a template for each playbook:

#### Template 1: Base LXC Configuration

1. Navigate to: **Task Templates**
2. Click **"New Template"**
3. Configure:
   - **Name**: `01 - Base LXC Setup`
   - **Playbook Filename**: `playbooks/01-base-lxc.yml`
   - **Inventory**: Select `Monitoring K3s`
   - **Environment**: Select `Monitoring Production`
   - **Repository**: Select `monit_homelab`
   - **SSH Key**: Select `k3s-monitor-root`
4. Click **Create**

#### Template 2: K3s Installation

1. Click **"New Template"** again
2. Configure:
   - **Name**: `02 - K3s Install`
   - **Playbook Filename**: `playbooks/02-k3s-install.yml`
   - **Inventory**: Select `Monitoring K3s`
   - **Environment**: Select `Monitoring Production`
   - **Repository**: Select `monit_homelab`
   - **SSH Key**: Select `k3s-monitor-root`
3. Click **Create**

---

## Running Playbooks via Semaphore UI

### Execute a Playbook

1. Navigate to: **Task Templates**
2. Select template (e.g., "01 - Base LXC Setup")
3. Click **"Run"** button
4. View real-time output in the **Tasks** section
5. Playbook output streams live in the UI

### View Task History

1. Navigate to: **Tasks**
2. See all past executions with status (Success/Failed)
3. Click any task to view full output logs

---

## Troubleshooting

### Check Semaphore logs
```bash
sudo journalctl -u semaphore -f
```

### Check database
```bash
sudo sqlite3 /var/lib/semaphore/semaphore.db ".tables"
```

### Verify Ansible is accessible
```bash
sudo -u semaphore ansible --version
```

### Permissions issues
Ensure semaphore user can access playbooks:
```bash
sudo chmod -R o+rX /home/monit_homelab/ansible
ls -la /home/monit_homelab/ansible
```

### Restart Semaphore
```bash
sudo systemctl restart semaphore
sudo systemctl status semaphore
```

### Check port availability
```bash
sudo ss -tlnp | grep 3000
```

### Reset admin password
If you forget your password:
```bash
cd /etc/semaphore
sudo semaphore user change-password --config config.json
```

---

## Security Notes

### Current Setup
- HTTP only (no TLS)
- Password-based authentication
- Admin access only

### Production Recommendations
1. **Add TLS**: Use nginx reverse proxy with Let's Encrypt
2. **Use SSH keys**: Replace password authentication with SSH keys
3. **Limit access**: Firewall rules to restrict port 3000 to management network
4. **Regular backups**: Backup `/var/lib/semaphore/semaphore.db`
5. **Update regularly**: Check for new Semaphore releases

---

## Backup & Restore

### Backup Database
```bash
sudo cp /var/lib/semaphore/semaphore.db /var/lib/semaphore/semaphore.db.backup-$(date +%Y%m%d)
```

### Restore Database
```bash
sudo systemctl stop semaphore
sudo cp /var/lib/semaphore/semaphore.db.backup-20231215 /var/lib/semaphore/semaphore.db
sudo systemctl start semaphore
```

---

## Upgrading Semaphore

```bash
# Stop service
sudo systemctl stop semaphore

# Backup database
sudo cp /var/lib/semaphore/semaphore.db /var/lib/semaphore/semaphore.db.backup-$(date +%Y%m%d)

# Download new version
SEMAPHORE_VERSION="v2.17.0"  # Update to new version
wget -O /tmp/semaphore.tar.gz \
  "https://github.com/semaphoreui/semaphore/releases/download/${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.tar.gz"

# Extract
sudo tar -xzf /tmp/semaphore.tar.gz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/semaphore

# Start service
sudo systemctl start semaphore
sudo systemctl status semaphore

# Verify version
semaphore version
```

---

## Next Steps

After Semaphore is set up:
1. Run "01 - Base LXC Setup" template
2. Run "02 - K3s Install" template
3. Verify K3s cluster: `kubectl --kubeconfig ~/.kube/monitoring-k3s.yaml get nodes`
4. Proceed to Phase 2: Deploy monitoring stack via ArgoCD

---

## Additional Resources

- [Semaphore Documentation](https://docs.semaphoreui.com/)
- [Semaphore GitHub](https://github.com/semaphoreui/semaphore)
- [Ansible Documentation](https://docs.ansible.com/)
