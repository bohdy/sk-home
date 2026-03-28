# Keep the managed switch identity explicit so outputs and shared tags stay
# aligned with the per-device state boundary.
locals {
  mikrotik_device = {
    key     = "switch_1np"
    name    = "Switch 1NP"
    role    = "switch"
    hosturl = var.mikrotik_hosturl
  }
}

# Reuse the shared RouterOS interface module so Switch 1NP can own its own
# state without duplicating bridge and VLAN resource logic.
module "interfaces" {
  source = "../../../../modules/routeros-device-interfaces"

  providers = {
    routeros = routeros
  }

  project_name           = var.project_name
  environment            = var.environment
  site_name              = var.site_name
  stack_name             = "network-core-interfaces-switch-1np"
  device_key             = local.mikrotik_device.key
  device_name            = local.mikrotik_device.name
  device_role            = local.mikrotik_device.role
  additional_tags        = var.additional_tags
  ethernet_interfaces    = var.ethernet_interfaces
  bridge                 = var.bridge
  bridge_ports           = var.bridge_ports
  bridge_vlans           = var.bridge_vlans
  vlan_interfaces        = var.vlan_interfaces
  six_to_four_interfaces = {}
}
