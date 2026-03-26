# Build a reusable stack context for router and switch resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "network-core"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Keep device endpoint metadata in one place so resources and outputs can
  # refer to the managed MikroTik inventory consistently.
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

  # Normalize DHCP scope inputs so resources can iterate consistently and keep
  # per-scope naming derived from a single source of truth.
  dhcp_scopes = {
    for name, scope in var.dhcp_scopes :
    name => merge(scope, { name = name })
  }
}

# Create a dedicated RouterOS pool for each DHCP scope managed on the gateway.
resource "routeros_ip_pool" "dhcp_scope" {
  provider = routeros.gw

  for_each = local.dhcp_scopes

  name = each.value.pool_name

  # Keep the DHCP range explicit so Terraform matches the intended pool bounds.
  ranges = [
    "${each.value.range_start}-${each.value.range_end}",
  ]

  comment = try(each.value.comment, null)
}

# Create one DHCP server per declared scope on the gateway and bind it to the
# intended interface and address pool.
resource "routeros_ip_dhcp_server" "dhcp_scope" {
  provider = routeros.gw

  for_each = local.dhcp_scopes

  name         = each.value.name
  interface    = each.value.interface
  address_pool = routeros_ip_pool.dhcp_scope[each.key].name
  lease_time   = each.value.lease_time
  add_arp      = each.value.add_arp
  comment      = try(each.value.comment, null)
}

# Attach per-subnet gateway, DNS, and domain settings for each DHCP scope.
resource "routeros_ip_dhcp_server_network" "dhcp_scope" {
  provider = routeros.gw

  for_each = local.dhcp_scopes

  address    = each.value.subnet
  gateway    = each.value.gateway
  dns_server = each.value.dns_servers
  domain     = try(each.value.domain, null)
  comment    = try(each.value.comment, null)
}
