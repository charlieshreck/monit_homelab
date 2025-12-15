# NVMe-oF Setup Guide for TrueNAS Scale → K3s Monitoring Cluster

This guide walks through setting up NVMe over Fabrics (NVMe-oF) TCP from TrueNAS Scale to the K3s monitoring cluster for high-performance storage.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ TrueNAS Scale (10.30.0.120) - NVMe-oF Target                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ ZFS Volumes (zvols)                                         │ │
│ │ ├─ Restormal/victoria-metrics (200GB) → Namespace nsid 1   │ │
│ │ └─ Trelawney/victoria-logs (500GB) → Namespace nsid 2      │ │
│ │                                                             │ │
│ │ NVMe-oF TCP Target                                          │ │
│ │ └─ nqn.2024-12.local.truenas:monitoring                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓ NVMe-oF TCP
┌─────────────────────────────────────────────────────────────────┐
│ K3s Monitor LXC (10.30.0.20) - NVMe-oF Initiator               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ nvme-cli installed                                          │ │
│ │ Connected namespaces:                                       │ │
│ │ ├─ /dev/nvme0n1 (200GB) → VictoriaMetrics PV              │ │
│ │ └─ /dev/nvme0n2 (500GB) → VictoriaLogs PV                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Benefits of NVMe-oF vs NFS

- **Lower Latency**: Direct block access, no file system overhead
- **Higher IOPS**: Better for time-series databases like VictoriaMetrics
- **Native Block Device**: Kubernetes can format with ext4/xfs
- **Better Performance**: ~10x lower latency than NFS for small random I/O

## Prerequisites

- ✅ TrueNAS Scale installed (10.30.0.120)
- ✅ K3s cluster running (10.30.0.20)
- ✅ Network connectivity between TrueNAS and K3s
- ⚠️ TrueNAS web UI access (http://10.30.0.120)

## Part 1: TrueNAS Scale Configuration (Target Side)

### Step 1: Check NVMe-oF Support

TrueNAS Scale has built-in NVMe-oF support. Check via web UI:

1. Go to **System → Advanced Settings**
2. Verify kernel modules are loaded (or will be on first use)

### Step 2: Create ZFS Volumes (zvols)

**In TrueNAS Web UI:**

1. Navigate to **Storage → Pools**

2. **Create Victoria Metrics zvol:**
   - Click pool name (e.g., **Restormal** or create new pool)
   - Click **Add Zvol**
   - **Name**: `victoria-metrics`
   - **Size**: `200 GiB`
   - **Block size**: `16 KiB` (optimal for databases)
   - **Compression**: `LZ4` (recommended)
   - **Sparse**: Disabled
   - Click **Save**

3. **Create Victoria Logs zvol:**
   - Select pool (e.g., **Trelawney** or create new pool)
   - Click **Add Zvol**
   - **Name**: `victoria-logs`
   - **Size**: `500 GiB`
   - **Block size**: `16 KiB`
   - **Compression**: `LZ4`
   - **Sparse**: Disabled
   - Click **Save**

**Expected zvol paths:**
- `/dev/zvol/Restormal/victoria-metrics`
- `/dev/zvol/Trelawney/victoria-logs`

### Step 3: Enable and Configure iSCSI Service (TrueNAS Scale NVMe-oF Alternative)

**Note:** As of TrueNAS Scale 24.10, native NVMe-oF configuration is done via CLI. The web UI primarily supports iSCSI.

**Two options:**

#### Option A: Use iSCSI (Web UI, Similar Performance)

If NVMe-oF CLI setup is complex, iSCSI is a solid alternative with web UI support:

1. Go to **Shares → Block (iSCSI)**
2. Click **Wizard**
3. Configure target and extent for each zvol
4. Connect from K3s using `iscsiadm`

*Skip to "Alternative: iSCSI Setup" section below if choosing this.*

#### Option B: Configure NVMe-oF TCP via SSH/Shell (Recommended for Performance)

**We need SSH access to configure NVMe-oF. Two options:**

**Option 1: Use TrueNAS Shell (Web UI)**
- Navigate to **System → Shell** in TrueNAS web UI
- Execute commands directly in browser

**Option 2: Enable SSH with public key** (if not already):
- Go to **System → Services → SSH**
- Click Edit
- Add this public key to **truenas_admin** user:
  ```
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+TwYgKq6PpeB2Vt0dai7NSA79YsqsBFsO1BM/ddkF8 root@iac
  ```
- Or enable password authentication

### Step 4: Configure NVMe-oF Target (via Shell)

**Execute in TrueNAS Shell or SSH:**

```bash
# Check if nvmet kernel module is loaded
lsmod | grep nvmet
# If not loaded:
modprobe nvmet
modprobe nvmet-tcp

# Create NVMe-oF target
mkdir -p /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring
cd /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring

# Allow any host (or specify K3s host NQN later)
echo 1 > attr_allow_any_host

# Create namespace 1 (VictoriaMetrics - 200GB)
mkdir namespaces/1
cd namespaces/1
echo "/dev/zvol/Restormal/victoria-metrics" > device_path
echo 1 > enable
cd ../..

# Create namespace 2 (VictoriaLogs - 500GB)
mkdir namespaces/2
cd namespaces/2
echo "/dev/zvol/Trelawney/victoria-logs" > device_path
echo 1 > enable
cd ../..

# Create TCP port
mkdir /sys/kernel/config/nvmet/ports/1
cd /sys/kernel/config/nvmet/ports/1
echo "10.30.0.120" > addr_traddr
echo "tcp" > addr_trtype
echo "4420" > addr_trsvcid  # NVMe-oF TCP default port
echo "ipv4" > addr_adrfam

# Link subsystem to port
ln -s /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring \
      /sys/kernel/config/nvmet/ports/1/subsystems/

# Verify configuration
dmesg | grep nvmet
```

### Step 5: Persist NVMe-oF Configuration (TrueNAS)

Create a systemd service or init script to configure NVMe-oF on boot:

```bash
# Create configuration script
cat > /root/nvmeof-setup.sh << 'EOF'
#!/bin/bash
# NVMe-oF Target Setup Script

# Load modules
modprobe nvmet
modprobe nvmet-tcp

# Create subsystem
mkdir -p /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring
cd /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring
echo 1 > attr_allow_any_host

# Namespace 1 - VictoriaMetrics
mkdir -p namespaces/1
echo "/dev/zvol/Restormal/victoria-metrics" > namespaces/1/device_path
echo 1 > namespaces/1/enable

# Namespace 2 - VictoriaLogs
mkdir -p namespaces/2
echo "/dev/zvol/Trelawney/victoria-logs" > namespaces/2/device_path
echo 1 > namespaces/2/enable

# Create port
mkdir -p /sys/kernel/config/nvmet/ports/1
cd /sys/kernel/config/nvmet/ports/1
echo "10.30.0.120" > addr_traddr
echo "tcp" > addr_trtype
echo "4420" > addr_trsvcid
echo "ipv4" > addr_adrfam

# Link subsystem
ln -sf /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring \
       /sys/kernel/config/nvmet/ports/1/subsystems/

echo "NVMe-oF target configured successfully"
EOF

chmod +x /root/nvmeof-setup.sh

# Create systemd service
cat > /etc/systemd/system/nvmeof-target.service << 'EOF'
[Unit]
Description=NVMe-oF Target Configuration
After=network.target zfs.target

[Service]
Type=oneshot
ExecStart=/root/nvmeof-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable nvmeof-target
systemctl start nvmeof-target
systemctl status nvmeof-target
```

### Step 6: Verify Target Configuration

```bash
# Check subsystems
ls /sys/kernel/config/nvmet/subsystems/

# Check namespaces
ls /sys/kernel/config/nvmet/subsystems/nqn.2024-12.local.truenas:monitoring/namespaces/

# Check ports
cat /sys/kernel/config/nvmet/ports/1/addr_traddr
cat /sys/kernel/config/nvmet/ports/1/addr_trsvcid

# Verify listening
ss -tlnp | grep 4420
```

Expected output: Port 4420 should be listening on 10.30.0.120

---

## Part 2: K3s Cluster Configuration (Initiator Side)

### Step 7: Install NVMe-oF Client Tools on K3s Node

SSH to K3s LXC (10.30.0.20):

```bash
ssh root@10.30.0.20

# Update and install nvme-cli
apt-get update
apt-get install -y nvme-cli

# Load NVMe-oF TCP module
modprobe nvme-tcp
echo "nvme-tcp" >> /etc/modules-load.d/nvme-tcp.conf

# Verify nvme-cli
nvme version
```

### Step 8: Discover and Connect to NVMe-oF Target

```bash
# Discover available subsystems
nvme discover -t tcp -a 10.30.0.120 -s 4420

# Expected output:
# Discovery Log Number of Records 1, Generation counter 1
# =====Discovery Log Entry 0======
# trtype:  tcp
# adrfam:  ipv4
# subtype: nvme subsystem
# treq:    not specified
# portid:  1
# trsvcid: 4420
# subnqn:  nqn.2024-12.local.truenas:monitoring
# traddr:  10.30.0.120

# Connect to the subsystem
nvme connect -t tcp -a 10.30.0.120 -s 4420 -n nqn.2024-12.local.truenas:monitoring

# Verify connection
nvme list

# Expected output:
# Node             SN                   Model                      Namespace Usage                      Format
# /dev/nvme0n1     <serial>             Linux                      1         214.75 GB / 214.75 GB    512 B + 0 B
# /dev/nvme0n2     <serial>             Linux                      2         536.87 GB / 536.87 GB    512 B + 0 B

# Check block devices
lsblk | grep nvme
```

### Step 9: Persist NVMe-oF Connection (K3s Node)

Create systemd service for automatic connection on boot:

```bash
# Create connection script
cat > /usr/local/bin/nvmeof-connect.sh << 'EOF'
#!/bin/bash
modprobe nvme-tcp
sleep 2
nvme connect -t tcp -a 10.30.0.120 -s 4420 -n nqn.2024-12.local.truenas:monitoring
EOF

chmod +x /usr/local/bin/nvmeof-connect.sh

# Create systemd service
cat > /etc/systemd/system/nvmeof-initiator.service << 'EOF'
[Unit]
Description=NVMe-oF Initiator Connection
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvmeof-connect.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable service
systemctl daemon-reload
systemctl enable nvmeof-initiator
systemctl status nvmeof-initiator
```

### Step 10: Format and Mount NVMe Devices (Test)

```bash
# Format namespace 1 (VictoriaMetrics)
mkfs.ext4 -L victoria-metrics /dev/nvme0n1

# Format namespace 2 (VictoriaLogs)
mkfs.ext4 -L victoria-logs /dev/nvme0n2

# Test mount
mkdir -p /mnt/victoria-metrics /mnt/victoria-logs
mount /dev/nvme0n1 /mnt/victoria-metrics
mount /dev/nvme0n2 /mnt/victoria-logs

# Verify
df -h | grep nvme

# Test write
dd if=/dev/zero of=/mnt/victoria-metrics/test.dat bs=1M count=100 oflag=direct
dd if=/dev/zero of=/mnt/victoria-logs/test.dat bs=1M count=100 oflag=direct

# Unmount (Kubernetes will handle mounting)
umount /mnt/victoria-metrics
umount /mnt/victoria-logs
```

---

## Part 3: Update Kubernetes Manifests for NVMe-oF

### Step 11: Update PersistentVolume Definitions

Update the PV manifests to use local NVMe block devices instead of NFS:

**VictoriaMetrics PV:**
```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoria-metrics-pv
  labels:
    app: victoria-metrics
    storage: nvme-of
spec:
  capacity:
    storage: 200Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-nvme
  local:
    path: /dev/nvme0n1
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - k3s-monitor  # K3s node hostname
```

**VictoriaLogs PV:**
```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoria-logs-pv
  labels:
    app: victoria-logs
    storage: nvme-of
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-nvme
  local:
    path: /dev/nvme0n2
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - k3s-monitor
```

**PVCs remain the same** but update storageClassName:
```yaml
storageClassName: local-nvme  # Changed from nfs-victoria-metrics
```

---

## Troubleshooting

### TrueNAS Side

```bash
# Check if nvmet modules are loaded
lsmod | grep nvmet

# Check target configuration
ls -la /sys/kernel/config/nvmet/subsystems/
ls -la /sys/kernel/config/nvmet/ports/

# Check port listening
ss -tlnp | grep 4420

# View kernel logs
dmesg | grep nvmet | tail -20

# Check zvol exists
ls -la /dev/zvol/Restormal/victoria-metrics
ls -la /dev/zvol/Trelawney/victoria-logs
```

### K3s Side

```bash
# Check nvme-cli installed
nvme version

# Check module loaded
lsmod | grep nvme_tcp

# Test connectivity
nc -zv 10.30.0.120 4420

# Discover targets
nvme discover -t tcp -a 10.30.0.120 -s 4420

# List connected devices
nvme list

# Check block devices
lsblk | grep nvme

# Disconnect (if needed)
nvme disconnect -n nqn.2024-12.local.truenas:monitoring
```

### Performance Testing

```bash
# Test sequential write performance
fio --name=seqwrite --filename=/dev/nvme0n1 --size=1G --bs=1M \
    --rw=write --direct=1 --ioengine=libaio --iodepth=32

# Test random IOPS
fio --name=randiops --filename=/dev/nvme0n1 --size=1G --bs=4k \
    --rw=randwrite --direct=1 --ioengine=libaio --iodepth=64 --runtime=30
```

---

## Alternative: iSCSI Setup (Easier Web UI Configuration)

If NVMe-oF proves difficult, iSCSI provides similar performance with full web UI support:

### TrueNAS iSCSI Configuration

1. **Shares → Block (iSCSI) → Wizard**
2. **Create Extent** (one per zvol)
3. **Create Target** (nqn-style naming)
4. **Create Portal** (10.30.0.120:3260)
5. **Associate** extent → target

### K3s iSCSI Client

```bash
apt-get install -y open-iscsi
iscsiadm -m discovery -t st -p 10.30.0.120
iscsiadm -m node --login
```

---

## Summary

After completion, you'll have:
- ✅ 200GB NVMe-oF block device for VictoriaMetrics
- ✅ 500GB NVMe-oF block device for VictoriaLogs
- ✅ Sub-millisecond latency storage
- ✅ Direct block device access from Kubernetes
- ✅ Persistent connections on boot

Which path would you like to take?
1. **NVMe-oF TCP** (best performance, CLI configuration)
2. **iSCSI** (similar performance, web UI configuration)
3. **NFS** (simplest, web UI, slightly lower performance)
