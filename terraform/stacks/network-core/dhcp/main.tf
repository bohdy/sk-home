# Build a reusable stack context for gateway DHCP resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "network-core-dhcp"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Load the shared VLAN catalog so DHCP reuses the same canonical RouterOS
  # interface names as the interface roots.
  vlan_catalog = yamldecode(file("${path.module}/../vlans.yaml")).vlans

  # Normalize DHCP scope inputs so the resource graph can derive per-scope
  # names and VLAN-backed interface names from one source of truth.
  dhcp_scopes = {
    for name, scope in var.dhcp_scopes :
    name => merge(scope, {
      name      = name
      interface = local.vlan_catalog[scope.vlan_key].interface_name
    })
  }

  # Keep reservation metadata keyed and normalized so static lease resources can
  # validate against the declared server inventory.
  dhcp_reservations = {
    for name, reservation in var.dhcp_reservations :
    name => merge(reservation, { name = name })
  }

  # Flatten nested option-set definitions into individual option records while
  # still preserving the parent set key for later joins.
  dhcp_options = length(var.dhcp_option_sets) == 0 ? {} : merge([
    for option_set_key, option_set in var.dhcp_option_sets : {
      for option_key, option in option_set.options :
      "${option_set_key}.${option_key}" => merge(option, {
        key            = option_key
        option_set_key = option_set_key
      })
    }
  ]...)
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

  name                      = each.value.name
  interface                 = each.value.interface
  address_pool              = routeros_ip_pool.dhcp_scope[each.key].name
  lease_time                = each.value.lease_time
  add_arp                   = each.value.add_arp
  dynamic_lease_identifiers = "client-mac,client-id"
  comment                   = try(each.value.comment, null)
}

# Attach per-subnet gateway, DNS, domain, and optional DHCP option-set
# settings for each scope.
resource "routeros_ip_dhcp_server_network" "dhcp_scope" {
  provider = routeros.gw

  for_each = local.dhcp_scopes

  address         = each.value.subnet
  gateway         = each.value.gateway
  dns_server      = each.value.dns_servers
  domain          = try(each.value.domain, null)
  dhcp_option_set = try(routeros_ip_dhcp_server_option_sets.dhcp_option_set[each.value.option_set].name, null)
  comment         = try(each.value.comment, null)
}

# Manage one static lease per declared reservation so address ownership remains
# committed and reviewable in version control.
resource "routeros_ip_dhcp_server_lease" "reservation" {
  provider = routeros.gw

  for_each = local.dhcp_reservations

  server      = routeros_ip_dhcp_server.dhcp_scope[each.value.server].name
  address     = each.value.address
  mac_address = each.value.mac_address
  comment     = try(each.value.comment, null)
}

# Create the individual DHCP option objects before assembling them into reusable
# option sets that can be attached to a scope.
resource "routeros_ip_dhcp_server_option" "dhcp_option" {
  provider = routeros.gw

  for_each = local.dhcp_options

  name    = each.value.name
  code    = each.value.code
  value   = each.value.value
  comment = try(each.value.comment, null)
}

# Assemble the per-option resources into RouterOS option sets so one scope can
# reference a named bundle instead of repeating option wiring.
resource "routeros_ip_dhcp_server_option_sets" "dhcp_option_set" {
  provider = routeros.gw

  for_each = var.dhcp_option_sets

  name = each.value.name

  # RouterOS stores option-set membership as a comma-separated option list, so
  # Terraform derives that string from the declared option inventory.
  options = join(",", [
    for option_key in sort(keys(each.value.options)) :
    routeros_ip_dhcp_server_option.dhcp_option["${each.key}.${option_key}"].name
  ])
}
