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
    ethernet_interfaces      = var.ethernet_interfaces
    bridge                   = var.bridge
    vlan_catalog             = var.vlan_catalog
    bridge_ports             = var.bridge_ports
    bridge_vlan_keys         = var.bridge_vlan_keys
    device_vlans             = var.device_vlans
    bridge_vlans             = local.bridge_vlan_inventory
    vlan_interfaces          = local.vlan_interface_inventory
    six_to_four_interfaces   = var.six_to_four_interfaces
    ipv4_interface_addresses = var.ipv4_interface_addresses
    ipv6_interface_addresses = var.ipv6_interface_addresses
  }
}
