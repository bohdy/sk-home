# Expose the resolved stack context so the interfaces root can be validated
# before operators point it at live RouterOS devices.
output "stack_context" {
  description = "Resolved root-module context for the nested interfaces stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}

# Expose the managed MikroTik devices without leaking credentials so operators
# can confirm the intended RouterOS endpoints for this nested root.
output "mikrotik_devices" {
  description = "Configured MikroTik devices managed by the interfaces stack."
  value       = local.mikrotik_devices
}

# Expose the committed bridge and interface inventory so local review can
# confirm the shape Terraform will apply without reading each variable block.
output "interface_inventory" {
  description = "Committed non-sensitive interface inventory managed by the interfaces stack."
  value = {
    ethernet_interfaces = var.ethernet_interfaces
    gw_bridge           = var.gw_bridge
    gw_bridge_ports     = var.gw_bridge_ports
    gw_bridge_vlans     = var.gw_bridge_vlans
    gw_vlan_interfaces  = var.gw_vlan_interfaces
    gw_6to4_interfaces  = var.gw_6to4_interfaces
  }
}
