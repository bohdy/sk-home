# Build a reusable stack context for interface-focused gateway and switch
# resources that deserve their own Terraform state.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "network-core-interfaces"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Normalize physical interface definitions into one keyed collection so the
  # provider-specific resource blocks can filter by device without duplicating
  # inventory data in multiple variables.
  ethernet_interface_inventory = length(var.ethernet_interfaces) == 0 ? {} : merge([
    for device_name, interfaces in var.ethernet_interfaces : {
      for interface_name, interface in interfaces :
      "${device_name}.${interface_name}" => merge(interface, {
        device       = device_name
        factory_name = interface_name
        name         = interface_name
      })
    }
  ]...)

  # Keep VLAN interfaces keyed by their RouterOS names so comments and bridge
  # parent bindings can be derived from committed data rather than literals.
  gw_vlan_interface_inventory = {
    for interface_name, interface in var.gw_vlan_interfaces :
    interface_name => merge(interface, { name = interface_name })
  }

  # Keep 6to4 tunnel definitions keyed by RouterOS name so tunnel resources can
  # be added later without changing the root data shape.
  gw_6to4_interface_inventory = {
    for interface_name, interface in var.gw_6to4_interfaces :
    interface_name => merge(interface, { name = interface_name })
  }

  # Normalize bridge ports from keyed data so pvid and frame-type logic stays
  # reviewable by interface name.
  gw_bridge_port_inventory = {
    for interface_name, port in var.gw_bridge_ports :
    interface_name => merge(port, { interface = interface_name })
  }

  # Normalize bridge VLAN records so resource instances can expose logical
  # labels without depending on array ordering.
  gw_bridge_vlan_inventory = {
    for vlan_name, vlan in var.gw_bridge_vlans :
    vlan_name => merge(vlan, { name = vlan_name })
  }

  # Keep the managed device endpoint inventory visible in this nested root so
  # operators can confirm which RouterOS devices the stack targets.
  mikrotik_devices = {
    gw = {
      name    = "GW"
      hosturl = var.mikrotik_gw_hosturl
      role    = "gateway"
    }
    switch_1pp = {
      name    = "Switch 1PP"
      hosturl = var.mikrotik_switch_1pp_hosturl
      role    = "switch"
    }
    switch_1np = {
      name    = "Switch 1NP"
      hosturl = var.mikrotik_switch_1np_hosturl
      role    = "switch"
    }
  }
}

# Manage gateway Ethernet comments through update-only resources so Terraform
# can annotate the live physical ports without recreating them.
resource "routeros_interface_ethernet" "gw" {
  provider = routeros.gw

  for_each = {
    for inventory_key, interface in local.ethernet_interface_inventory :
    inventory_key => interface
    if interface.device == "gw"
  }

  factory_name = each.value.factory_name
  name         = each.value.name
  comment      = try(each.value.comment, null)
  disabled     = each.value.disabled
}

# Manage Switch 1PP Ethernet comments in the same stack so physical uplink
# labels stay version-controlled with the broader interface inventory.
resource "routeros_interface_ethernet" "switch_1pp" {
  provider = routeros.switch_1pp

  for_each = {
    for inventory_key, interface in local.ethernet_interface_inventory :
    inventory_key => interface
    if interface.device == "switch_1pp"
  }

  factory_name = each.value.factory_name
  name         = each.value.name
  comment      = try(each.value.comment, null)
  disabled     = each.value.disabled
}

# Manage Switch 1NP Ethernet comments alongside the gateway inventory so uplink
# and AP port descriptions remain committed in one place.
resource "routeros_interface_ethernet" "switch_1np" {
  provider = routeros.switch_1np

  for_each = {
    for inventory_key, interface in local.ethernet_interface_inventory :
    inventory_key => interface
    if interface.device == "switch_1np"
  }

  factory_name = each.value.factory_name
  name         = each.value.name
  comment      = try(each.value.comment, null)
  disabled     = each.value.disabled
}

# Manage the gateway's main LAN bridge separately from bridge ports so bridge
# lifecycle and port membership can evolve independently in the state graph.
resource "routeros_interface_bridge" "gw" {
  provider = routeros.gw

  name           = var.gw_bridge.name
  comment        = try(var.gw_bridge.comment, null)
  vlan_filtering = try(var.gw_bridge.vlan_filtering, true)
  disabled       = try(var.gw_bridge.disabled, false)
}

# Manage one gateway VLAN interface per committed VLAN so interface comments and
# bridge parent bindings remain synchronized in version control.
resource "routeros_interface_vlan" "gw" {
  provider = routeros.gw

  for_each = local.gw_vlan_interface_inventory

  name      = each.value.name
  interface = each.value.interface
  vlan_id   = each.value.vlan_id
  mtu       = try(each.value.mtu, null)
  comment   = try(each.value.comment, null)
  disabled  = each.value.disabled

  depends_on = [
    routeros_interface_bridge.gw,
  ]
}

# Manage one 6to4 tunnel interface per committed tunnel definition so `sit1`
# can evolve with the rest of the gateway interface state.
resource "routeros_interface_6to4" "gw" {
  provider = routeros.gw

  for_each = local.gw_6to4_interface_inventory

  name           = each.value.name
  mtu            = each.value.mtu
  local_address  = each.value.local_address
  remote_address = each.value.remote_address
  clamp_tcp_mss  = each.value.clamp_tcp_mss
  comment        = try(each.value.comment, null)
  disabled       = each.value.disabled
}

# Manage bridge membership and ingress behavior per gateway port so access,
# trunk, and hybrid links remain explicit in the committed desired state.
resource "routeros_interface_bridge_port" "gw" {
  provider = routeros.gw

  for_each = local.gw_bridge_port_inventory

  bridge            = routeros_interface_bridge.gw.name
  interface         = each.value.interface
  comment           = try(each.value.comment, null)
  pvid              = try(each.value.pvid, null)
  frame_types       = try(each.value.frame_types, null)
  ingress_filtering = try(each.value.ingress_filtering, null)
  disabled          = each.value.disabled

  depends_on = [
    routeros_interface_ethernet.gw,
    routeros_interface_bridge.gw,
  ]
}

# Manage one bridge VLAN table entry per committed VLAN record so tagged and
# untagged egress behavior stays aligned with the intended bridge topology.
resource "routeros_interface_bridge_vlan" "gw" {
  provider = routeros.gw

  for_each = local.gw_bridge_vlan_inventory

  bridge   = routeros_interface_bridge.gw.name
  comment  = try(each.value.comment, null)
  vlan_ids = each.value.vlan_ids
  tagged   = each.value.tagged
  untagged = each.value.untagged
  disabled = each.value.disabled

  depends_on = [
    routeros_interface_bridge.gw,
    routeros_interface_bridge_port.gw,
  ]
}
