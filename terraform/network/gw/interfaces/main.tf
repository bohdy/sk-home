// Build the gateway around one primary bridge so VLAN policy and access-port
// behavior stay centralized on the RouterOS side.
resource "routeros_interface_bridge" "bridge" {
  provider       = routeros.gw
  name           = "bridge"
  comment        = "Primary LAN bridge"
  arp            = "enabled"
  admin_mac      = "18:FD:74:CF:73:F0"
  vlan_filtering = true
  fast_forward   = true
}

// Attach interfaces with a PVID to the shared bridge while preserving a
// per-port PVID for untagged ingress traffic. Interfaces without a PVID are
// not attached to the bridge.
resource "routeros_interface_bridge_port" "bridge_port_ethernet" {
  for_each = {
    for k, v in var.interfaces : k => v if v.pvid != null && v.pvid != 0
  }
  provider  = routeros.gw
  bridge    = routeros_interface_bridge.bridge.name
  interface = each.value.name
  comment   = each.value.name
  pvid      = each.value.pvid
}

// Mirror the declarative interface inventory into RouterOS so comment metadata
// and port naming stay consistent with the bridge membership map.
resource "routeros_interface_ethernet" "ethernet" {
  for_each     = var.interfaces
  provider     = routeros.gw
  factory_name = each.value.name
  name         = each.value.name
  comment      = each.value.comment
}

resource "routeros_interface_vlan" "iface_vlan" {
  for_each = var.vlans
  provider = routeros.gw
  name     = "vlan${each.key}"
  // interface = "vlan${each.key}"
  interface = routeros_interface_bridge.bridge.name
  comment   = each.value.name
}

// Materialize the VLAN inventory onto the bridge from one source of truth,
// ensuring trunk membership and access-port exposure can be reviewed in code.
resource "routeros_interface_bridge_vlan" "bridge_vlan" {
  for_each = var.vlans
  provider = routeros.gw
  vlan_ids = [tonumber(each.key)]
  bridge   = routeros_interface_bridge.bridge.name
  tagged   = setunion([routeros_interface_bridge.bridge.name], each.value.tagged)
  untagged = each.value.untagged
  comment  = each.value.name
}

resource "routeros_ip_address" "ip_address" {
  for_each = {
    for k, v in var.interfaces : k => v if v.ip_address != null
  }
  provider  = routeros.gw
  address   = each.value.ip_address
  interface = each.value.name
  comment   = each.value.comment
}

resource "routeros_ip_address" "ip_address_vlan" {
  for_each = {
    for k, v in var.vlans : k => v if v.ip_address != null
  }
  provider  = routeros.gw
  address   = each.value.ip_address
  interface = "vlan${each.key}"
  comment   = each.value.name
}

// Collect all unique interface list names referenced across interfaces and vlans
// to ensure all required lists are created before members are assigned.
locals {
  interface_lists = {
    for name in distinct(concat(
      [for v in var.interfaces : v.iface_list if v.iface_list != null],
      [for v in var.vlans : v.iface_list if v.iface_list != null]
    )) : name => true
  }
}

// Create all required interface lists dynamically from the merged local to ensure
// they exist before members are assigned.
resource "routeros_interface_list" "lists" {
  for_each = local.interface_lists
  provider = routeros.gw
  name     = each.key
}

resource "routeros_interface_list_member" "list_member_ether" {
  provider = routeros.gw
  for_each = {
    for k, v in var.interfaces : k => v if v.iface_list != null
  }
  interface = each.key
  list      = each.value.iface_list
}

resource "routeros_interface_list_member" "list_member_vlan" {
  provider = routeros.gw
  for_each = {
    for k, v in var.vlans : k => v if v.iface_list != null
  }
  interface = "vlan${each.key}"
  list      = each.value.iface_list
}
