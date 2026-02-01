locals {
  # MAC address generation for static DHCP assignment
  # Pattern: 52:54:00:10:10:XX where XX is last octet of IP in hex
  # IP 10.10.0.30 → 0x1E (30 in hex)
  monitoring_node_mac = "52:54:00:10:10:1E"

  # Single node configuration
  node_config = merge(var.monitoring_node, {
    mac_address = local.monitoring_node_mac
  })

  # Cluster endpoint (single node)
  cluster_endpoint = "https://${var.monitoring_node.ip}:6443"

  # Network configuration
  network = {
    bridge  = var.network_bridge
    network = "10.10.0.0/24"
    gateway = var.monitoring_gateway
  }
}
