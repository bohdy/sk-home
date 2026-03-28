# Build a reusable stack context for gateway routing resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "network-core-routing"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Normalize committed IPv4 routes so future resource and output changes can
  # derive behavior from one source of truth.
  ipv4_static_routes = {
    for name, route in var.ipv4_static_routes :
    name => merge(route, { name = name })
  }

  # Normalize committed IPv6 routes separately because the provider exposes a
  # dedicated IPv6 route resource instead of a shared cross-family primitive.
  ipv6_static_routes = {
    for name, route in var.ipv6_static_routes :
    name => merge(route, { name = name })
  }
}

# Manage one committed IPv4 static route per declared destination so GW route
# intent stays reviewable in version control and CI.
resource "routeros_ip_route" "static_route" {
  provider = routeros.gw

  for_each = local.ipv4_static_routes

  dst_address   = each.value.dst_address
  gateway       = each.value.blackhole ? var.blackhole_gateway_placeholder : ""
  blackhole     = each.value.blackhole
  routing_table = each.value.routing_table
  distance      = each.value.distance
  disabled      = each.value.disabled
  comment       = try(each.value.comment, null)
}

# Manage one committed IPv6 static route per declared destination using the
# dedicated IPv6 resource so RouterOS state stays family-correct.
resource "routeros_ipv6_route" "static_route" {
  provider = routeros.gw

  for_each = local.ipv6_static_routes

  dst_address   = each.value.dst_address
  gateway       = each.value.blackhole ? var.blackhole_gateway_placeholder : ""
  blackhole     = each.value.blackhole
  routing_table = each.value.routing_table
  distance      = each.value.distance
  disabled      = each.value.disabled
  comment       = try(each.value.comment, null)
}
