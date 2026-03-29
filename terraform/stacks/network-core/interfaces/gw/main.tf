# Keep the managed gateway identity explicit so outputs and shared tags stay
# aligned with the per-device state boundary.
locals {
  mikrotik_device = {
    key     = "gw"
    name    = "GW"
    role    = "gateway"
    hosturl = var.mikrotik_hosturl
  }

  # Load the shared VLAN catalog once so this root can reuse the same managed
  # VLAN IDs and interface names as the rest of network-core.
  vlan_catalog = yamldecode(file("${path.module}/../../vlans.yaml")).vlans
}

# Reuse the shared RouterOS interface module so the gateway root can own its
# own state without duplicating resource logic from the switch roots.
module "interfaces" {
  source = "../../../../modules/routeros-device-interfaces"

  providers = {
    routeros = routeros
  }

  project_name             = var.project_name
  environment              = var.environment
  site_name                = var.site_name
  stack_name               = "network-core-interfaces-gw"
  device_key               = local.mikrotik_device.key
  device_name              = local.mikrotik_device.name
  device_role              = local.mikrotik_device.role
  additional_tags          = var.additional_tags
  ethernet_interfaces      = var.ethernet_interfaces
  bridge                   = var.bridge
  vlan_catalog             = local.vlan_catalog
  bridge_ports             = var.bridge_ports
  bridge_vlans             = var.bridge_vlans
  derived_bridge_vlan_keys = var.derived_bridge_vlan_keys
  device_vlans             = var.device_vlans
  six_to_four_interfaces   = var.six_to_four_interfaces
}
