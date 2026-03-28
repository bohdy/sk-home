# Expose the resolved shared tag map so each root can confirm the common
# metadata derived from its committed inputs.
output "common_tags" {
  description = "Resolved common metadata tags for the managed device root."
  value       = local.common_tags
}

# Expose the committed non-sensitive inventory so callers can review the shape
# Terraform will manage without reading each variable block individually.
output "interface_inventory" {
  description = "Committed non-sensitive interface inventory managed by the module."
  value = {
    ethernet_interfaces    = var.ethernet_interfaces
    bridge                 = var.bridge
    bridge_ports           = var.bridge_ports
    bridge_vlans           = var.bridge_vlans
    vlan_interfaces        = var.vlan_interfaces
    six_to_four_interfaces = var.six_to_four_interfaces
  }
}
