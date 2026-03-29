# Build a reusable per-device context so one module can manage the gateway and
# switch interface roots without duplicating provider-specific resource logic.
locals {
  # Keep common tags consistent across roots while still allowing local
  # overrides for non-sensitive metadata.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = var.stack_name
      device      = var.device_key
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Normalize physical interface definitions into one keyed collection so
  # update-only RouterOS Ethernet resources can consume reviewable data.
  ethernet_interface_inventory = {
    for interface_name, interface in var.ethernet_interfaces :
    interface_name => merge(interface, {
      factory_name = interface_name
      name         = interface_name
    })
  }

  # Normalize the optional bridge object into a keyed collection so dependent
  # resources can use standard for_each patterns.
  bridge_inventory = var.bridge == null ? {} : {
    (var.bridge.name) = var.bridge
  }

  # Keep bridge name lookups explicit so dependent resources do not have to
  # reach back into nullable input objects directly.
  bridge_name = var.bridge == null ? null : var.bridge.name

  # Normalize the managed VLAN catalog so the module can derive RouterOS-facing
  # VLAN IDs and interface names from one shared keyed inventory.
  vlan_catalog = {
    for vlan_key, vlan in var.vlan_catalog :
    vlan_key => merge(vlan, { key = vlan_key })
  }

  # Keep 6to4 tunnel definitions keyed by RouterOS name so tunnel resources
  # can be imported or extended without changing the root data shape.
  six_to_four_interface_inventory = {
    for interface_name, interface in var.six_to_four_interfaces :
    interface_name => merge(interface, { name = interface_name })
  }

  # Normalize bridge ports from keyed data so symbolic VLAN references can be
  # resolved before RouterOS resources consume them.
  bridge_port_inventory = {
    for interface_name, port in var.bridge_ports :
    interface_name => merge(port, {
      interface = interface_name
      pvid = try(
        local.vlan_catalog[port.pvid_vlan].vlan_id,
        try(port.pvid, null)
      )
    })
  }

  # Collect explicit committed VLAN memberships from the bridge-port map so
  # bridge VLAN rows can be derived instead of hand-authored per device.
  explicit_vlan_keys = toset(concat(
    keys(var.device_vlans),
    flatten([
      for _, port in var.bridge_ports :
      concat(
        tolist(try(port.tagged_vlans, [])),
        tolist(try(port.untagged_vlans, []))
      )
    ])
  ))

  # Derive bridge VLAN records from the shared VLAN catalog and explicit port
  # membership lists so tagged and untagged forwarding stays synchronized.
  bridge_vlan_inventory = {
    for vlan_key in sort(tolist(local.explicit_vlan_keys)) :
    local.vlan_catalog[vlan_key].interface_name => {
      catalog_key = vlan_key
      name        = local.vlan_catalog[vlan_key].interface_name
      comment     = local.vlan_catalog[vlan_key].comment
      vlan_ids    = toset([tostring(local.vlan_catalog[vlan_key].vlan_id)])
      tagged = toset(concat(
        local.bridge_name == null ? [] : [local.bridge_name],
        [
          for interface_name, port in var.bridge_ports :
          interface_name if contains(tolist(try(port.tagged_vlans, [])), vlan_key)
        ]
      ))
      untagged = toset([
        for interface_name, port in var.bridge_ports :
        interface_name if contains(tolist(try(port.untagged_vlans, [])), vlan_key)
      ])
      disabled = try(var.device_vlans[vlan_key].disabled, false)
    }
  }

  # Build one VLAN interface per device-owned VLAN interface declaration so the
  # shared catalog controls RouterOS names and numeric VLAN IDs.
  vlan_interface_inventory = {
    for vlan_key, vlan in var.device_vlans :
    local.vlan_catalog[vlan_key].interface_name => {
      name      = local.vlan_catalog[vlan_key].interface_name
      interface = try(vlan.vlan_interface_parent, local.bridge_name)
      vlan_id   = local.vlan_catalog[vlan_key].vlan_id
      mtu       = try(vlan.vlan_interface_mtu, null)
      comment   = local.vlan_catalog[vlan_key].comment
      disabled  = try(vlan.disabled, false)
    } if try(vlan.create_vlan_interface, false)
  }
}

# Preserve the pre-refactor bridge VLAN instance addresses so the shared
# catalog migration does not force bridge VLAN destroy/create operations.
moved {
  from = routeros_interface_bridge_vlan.this["users"]
  to   = routeros_interface_bridge_vlan.this["vlan10"]
}

moved {
  from = routeros_interface_bridge_vlan.this["servers"]
  to   = routeros_interface_bridge_vlan.this["vlan20"]
}

moved {
  from = routeros_interface_bridge_vlan.this["management"]
  to   = routeros_interface_bridge_vlan.this["vlan100"]
}

moved {
  from = routeros_interface_bridge_vlan.this["cameras"]
  to   = routeros_interface_bridge_vlan.this["vlan101"]
}

moved {
  from = routeros_interface_bridge_vlan.this["aps"]
  to   = routeros_interface_bridge_vlan.this["vlan102"]
}

# Manage physical interface comments through update-only resources so Terraform
# can annotate live ports without recreating them.
resource "routeros_interface_ethernet" "this" {
  for_each = local.ethernet_interface_inventory

  factory_name = each.value.factory_name
  name         = each.value.name
  comment      = try(each.value.comment, null)
  disabled     = each.value.disabled
}

# Manage the device bridge separately from bridge ports so bridge lifecycle and
# port membership can evolve independently in the state graph.
resource "routeros_interface_bridge" "this" {
  for_each = local.bridge_inventory

  name           = each.value.name
  comment        = try(each.value.comment, null)
  vlan_filtering = try(each.value.vlan_filtering, true)
  disabled       = try(each.value.disabled, false)
}

# Manage one VLAN interface per committed VLAN so interface comments and bridge
# parent bindings remain synchronized in version control.
resource "routeros_interface_vlan" "this" {
  for_each = local.vlan_interface_inventory

  name      = each.value.name
  interface = each.value.interface
  vlan_id   = each.value.vlan_id
  mtu       = try(each.value.mtu, null)
  comment   = try(each.value.comment, null)
  disabled  = each.value.disabled

  depends_on = [
    routeros_interface_bridge.this,
  ]
}

# Manage one 6to4 tunnel interface per committed tunnel definition so tunnel
# settings can evolve with the rest of the device interface state.
resource "routeros_interface_6to4" "this" {
  for_each = local.six_to_four_interface_inventory

  name           = each.value.name
  mtu            = each.value.mtu
  local_address  = each.value.local_address
  remote_address = each.value.remote_address
  clamp_tcp_mss  = each.value.clamp_tcp_mss
  comment        = try(each.value.comment, null)
  disabled       = each.value.disabled
}

# Manage bridge membership and ingress behavior per port so access, trunk, and
# hybrid links remain explicit in the committed desired state.
resource "routeros_interface_bridge_port" "this" {
  for_each = local.bridge_port_inventory

  bridge            = local.bridge_name
  interface         = each.value.interface
  comment           = try(each.value.comment, null)
  pvid              = try(each.value.pvid, null)
  frame_types       = try(each.value.frame_types, null)
  ingress_filtering = try(each.value.ingress_filtering, null)
  disabled          = each.value.disabled

  depends_on = [
    routeros_interface_ethernet.this,
    routeros_interface_bridge.this,
  ]
}

# Manage one bridge VLAN table entry per committed VLAN record so tagged and
# untagged egress behavior stays aligned with the intended bridge topology.
resource "routeros_interface_bridge_vlan" "this" {
  for_each = local.bridge_vlan_inventory

  bridge   = local.bridge_name
  comment  = try(each.value.comment, null)
  vlan_ids = each.value.vlan_ids
  tagged   = each.value.tagged
  untagged = each.value.untagged
  disabled = each.value.disabled

  depends_on = [
    routeros_interface_bridge.this,
    routeros_interface_bridge_port.this,
  ]
}
