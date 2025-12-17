locals {
  # MAC address generation for static DHCP assignment
  # Pattern: 52:54:00:30:00:XX where XX is last octet of IP in hex
  # IP 10.30.0.20 → 0x14 (20 in hex)
  monitoring_node_mac = "52:54:00:30:00:14"

  # Single node configuration
  node_config = merge(var.monitoring_node, {
    mac_address = local.monitoring_node_mac
  })

  # Cluster endpoint (single node)
  cluster_endpoint = "https://${var.monitoring_node.ip}:6443"

  # Network configuration
  network = {
    bridge  = var.network_bridge
    network = "10.30.0.0/24"
    gateway = var.monitoring_gateway
  }
}
