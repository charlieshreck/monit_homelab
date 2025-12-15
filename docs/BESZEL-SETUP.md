# Beszel Configuration Guide

Beszel is a lightweight server monitoring hub. The hub runs in Kubernetes, and agents run on each system you want to monitor.

## Access

- **Web UI**: https://beszel.kernow.io
- **Internal**: http://10.30.0.20:30087 (HTTP) / 10.30.0.20:30088 (Agent port)

## Initial Setup

### 1. Access Beszel Web UI

Visit https://beszel.kernow.io and create an admin account on first login.

### 2. Generate SSH Key for Agents

Beszel uses SSH to connect to agents. The hub needs an SSH public key configured.

In the Beszel web UI:
1. Go to **Settings** → **SSH Keys**
2. Click **Generate New Key Pair**
3. Copy the **public key** (you'll need this for agents)
4. Save the settings

## Installing Beszel Agents

Install agents on systems you want to monitor. Agents connect back to the hub on port 45876.

### Option 1: Docker Agent (for VMs/LXCs with Docker)

```bash
# On the target system (e.g., Plex VM, TrueNAS)
docker run -d \
  --name beszel-agent \
  --restart unless-stopped \
  -p 45876:45876 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  henrygd/beszel-agent
```

### Option 2: Binary Agent (for Proxmox hosts, bare metal)

```bash
# Download agent
curl -sL "https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_$(uname -s)_$(uname -m | sed 's/x86_64/amd64/' | sed 's/armv7l/arm/').tar.gz" | tar -xz -O beszel-agent | sudo tee /usr/local/bin/beszel-agent > /dev/null && sudo chmod +x /usr/local/bin/beszel-agent

# Create systemd service
sudo tee /etc/systemd/system/beszel-agent.service > /dev/null <<EOF
[Unit]
Description=Beszel Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/beszel-agent
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable beszel-agent
sudo systemctl start beszel-agent
```

### Option 3: Kubernetes Agent (for monitoring the K3s cluster itself)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: beszel-agent
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: beszel-agent
  template:
    metadata:
      labels:
        app: beszel-agent
    spec:
      hostNetwork: true
      hostPID: true
      containers:
        - name: beszel-agent
          image: henrygd/beszel-agent:latest
          ports:
            - containerPort: 45876
              hostPort: 45876
          volumeMounts:
            - name: docker-sock
              mountPath: /var/run/docker.sock
              readOnly: true
      volumes:
        - name: docker-sock
          hostPath:
            path: /var/run/docker.sock
```

## Adding Systems to Beszel Hub

After installing agents, add them in the Beszel web UI:

1. Go to **Systems** → **Add System**
2. Fill in details:
   - **Name**: System name (e.g., "Proxmox Ruapehu")
   - **Host**: IP address (e.g., 10.10.0.10)
   - **Port**: 45876 (default agent port)
   - **SSH Public Key**: Paste the public key from Settings
3. Click **Add System**

The hub will connect to the agent via SSH tunnel on port 45876.

## Systems to Monitor

### Recommended Systems

| System | IP | Type | Priority |
|--------|-----|------|----------|
| **Proxmox Ruapehu** | 10.10.0.10 | Bare Metal | High |
| **Proxmox Carrick** | 10.30.0.10 | Bare Metal | High |
| **Plex VM** | 10.10.0.50 | VM | High |
| **TrueNAS** | 10.10.0.100 | VM | Medium |
| **K3s Monitoring** | 10.30.0.20 | LXC | Medium |
| **Talos Control** | 10.10.0.40 | VM | Low (read-only OS) |
| **Talos Worker 1** | 10.10.0.41 | VM | Low |
| **Talos Worker 2** | 10.10.0.42 | VM | Low |
| **Talos Worker 3** | 10.10.0.43 | VM | Low |

### Agent Installation Examples

**Proxmox Ruapehu (10.10.0.10):**
```bash
ssh root@10.10.0.10
# Install binary agent (systemd service)
curl -sL "https://github.com/henrygd/beszel/releases/latest/download/beszel-agent_Linux_amd64.tar.gz" | tar -xz -O beszel-agent | sudo tee /usr/local/bin/beszel-agent > /dev/null
sudo chmod +x /usr/local/bin/beszel-agent
# Create systemd service (see above)
```

**Plex VM (10.10.0.50):**
```bash
ssh root@10.10.0.50
# Plex already has Docker, use Docker agent
docker run -d --name beszel-agent --restart unless-stopped -p 45876:45876 -v /var/run/docker.sock:/var/run/docker.sock:ro henrygd/beszel-agent
```

**TrueNAS (10.10.0.100):**
TrueNAS Scale has Docker built-in:
1. Access TrueNAS web UI (10.10.0.100)
2. Apps → Discover Apps → Custom App
3. Image: `henrygd/beszel-agent:latest`
4. Port: 45876 → 45876
5. Volume: `/var/run/docker.sock` (read-only)

## Firewall Rules

Ensure port **45876** is accessible from the Beszel hub (10.30.0.20) to all monitored systems.

### Proxmox Firewall
```bash
# On Proxmox hosts
iptables -A INPUT -p tcp --dport 45876 -s 10.30.0.20 -j ACCEPT
```

### TrueNAS Firewall
Add firewall rule via System → General → Allow access from 10.30.0.20:45876

## Troubleshooting

### Agent not connecting
```bash
# Check agent is running
systemctl status beszel-agent  # For systemd
docker logs beszel-agent       # For Docker

# Check port is listening
ss -tlnp | grep 45876

# Test connectivity from hub
ssh root@10.30.0.20  # SSH into K3s LXC
nc -zv <target-ip> 45876
```

### SSH key issues
- Ensure you copied the **public key** from Beszel settings
- The agent must accept SSH connections on port 45876
- Check Beszel hub logs: `kubectl logs -n monitoring <beszel-pod>`

## Features

Beszel monitors:
- CPU usage
- Memory usage
- Disk usage
- Network traffic
- Process list
- Docker container stats (if Docker socket mounted)
- System uptime
- Load averages

All data stored in SQLite database (persistent via PVC in Kubernetes).

## Beszel Hub Configuration

Hub is already configured with:
- **Storage**: 2Gi persistent volume
- **Timezone**: Pacific/Auckland
- **Resources**: 50m CPU / 128Mi RAM (request)
- **Ports**: 8090 (web), 45876 (agent SSH)

Data persists in the `beszel-data` PVC.
