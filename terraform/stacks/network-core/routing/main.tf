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

  # Normalize BGP instances so per-instance resources and outputs can derive
  # names from one committed source of truth.
  bgp_instances = {
    for name, instance in var.bgp_instances :
    name => merge(instance, { name = name })
  }

  # Normalize BGP templates separately because connections can inherit from one
  # or more named templates managed in this same stack.
  bgp_templates = {
    for name, template in var.bgp_templates :
    name => merge(template, { name = name })
  }

  # Normalize BGP connections and materialize nested defaults so imported peer
  # state can converge without depending on provider-side implicit values.
  bgp_connections = {
    for name, connection in var.bgp_connections :
    name => merge(connection, {
      name = name
      output = try(connection.output, null) == null ? null : merge(
        {
          affinity                       = null
          as_override                    = false
          default_originate              = null
          default_prepend                = 0
          filter_chain                   = null
          filter_select                  = null
          keep_sent_attributes           = false
          network                        = null
          no_client_to_client_reflection = false
          no_early_cut                   = false
          redistribute                   = null
          remove_private_as              = false
        },
        connection.output
      )
    })
  }

  # Keep routing filter rules keyed by stable Terraform slugs because RouterOS
  # rules do not have first-class names that can serve as for_each keys.
  routing_filter_rules = {
    for name, rule in var.routing_filter_rules :
    name => merge(rule, { name = name })
  }
}

# Manage one committed IPv4 static route per declared destination so GW route
# intent stays reviewable in version control and CI.
resource "routeros_ip_route" "static_route" {
  provider = routeros.gw

  for_each = local.ipv4_static_routes

  dst_address = each.value.dst_address
  gateway     = each.value.blackhole ? var.blackhole_gateway_placeholder : ""
  # RouterOS treats blackhole as a presence flag rather than a meaningful
  # true/false value, and the provider currently refreshes these routes back as
  # false. Keep the argument present for blackhole routes while matching the
  # provider's readback value to avoid perpetual drift.
  blackhole     = each.value.blackhole ? false : null
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

  dst_address = each.value.dst_address
  gateway     = each.value.blackhole ? var.blackhole_gateway_placeholder : ""
  # Keep IPv6 blackhole handling aligned with the IPv4 workaround above so the
  # provider still emits the attribute while local plans stay convergent.
  blackhole     = each.value.blackhole ? false : null
  routing_table = each.value.routing_table
  distance      = each.value.distance
  disabled      = each.value.disabled
  comment       = try(each.value.comment, null)
}

# Manage one BGP instance per declared RouterOS instance so shared gateway
# routing identity and per-instance attributes stay committed in version control.
resource "routeros_routing_bgp_instance" "bgp_instance" {
  provider = routeros.gw

  for_each = local.bgp_instances

  name          = each.value.name
  as            = each.value.as
  comment       = try(each.value.comment, null)
  disabled      = each.value.disabled
  router_id     = try(each.value.router_id, null)
  routing_table = each.value.routing_table
  vrf           = each.value.vrf
}

# Manage reusable BGP templates so connection groups can inherit shared RouterOS
# peer behavior from one committed template inventory.
resource "routeros_routing_bgp_template" "bgp_template" {
  provider = routeros.gw

  for_each = local.bgp_templates

  name             = each.value.name
  as               = each.value.as
  comment          = try(each.value.comment, null)
  disabled         = each.value.disabled
  multihop         = try(each.value.multihop, null)
  routing_table    = each.value.routing_table
  templates        = length(each.value.templates) == 0 ? null : each.value.templates
  address_families = try(each.value.address_families, null)
  add_path_out     = try(each.value.add_path_out, null)
  keepalive_time   = try(each.value.keepalive_time, null)
  hold_time        = try(each.value.hold_time, null)
  nexthop_choice   = try(each.value.nexthop_choice, null)
  save_to          = try(each.value.save_to, null)
  use_bfd          = try(each.value.use_bfd, null)
  vrf              = each.value.vrf
}

# Manage routing filter rules first so exported BGP policy chains already exist
# before Terraform reconciles any connection that references them.
resource "routeros_routing_filter_rule" "routing_filter_rule" {
  provider = routeros.gw

  for_each = local.routing_filter_rules

  chain    = each.value.chain
  comment  = try(each.value.comment, null)
  disabled = each.value.disabled
  rule     = each.value.rule
}

# Manage one BGP connection per declared live session so peer-specific local,
# remote, and export-policy behavior stays reviewable and importable.
resource "routeros_routing_bgp_connection" "bgp_connection" {
  provider = routeros.gw

  for_each = local.bgp_connections

  name             = each.value.name
  as               = each.value.as
  comment          = try(each.value.comment, null)
  disabled         = each.value.disabled
  instance         = try(each.value.instance, null) == null ? null : routeros_routing_bgp_instance.bgp_instance[each.value.instance].name
  routing_table    = each.value.routing_table
  vrf              = each.value.vrf
  address_families = try(each.value.address_families, null)
  connect          = try(each.value.connect, null)
  multihop         = try(each.value.multihop, null)
  templates = length(each.value.templates) == 0 ? null : toset([
    for template_name in sort(tolist(each.value.templates)) :
    routeros_routing_bgp_template.bgp_template[template_name].name
  ])

  local {
    role    = each.value.local.role
    address = try(each.value.local.address, null)
    port    = try(each.value.local.port, null)
    ttl     = try(each.value.local.ttl, null)
  }

  dynamic "output" {
    for_each = each.value.output == null ? [] : [each.value.output]

    content {
      affinity                       = output.value.affinity
      as_override                    = output.value.as_override
      default_originate              = output.value.default_originate
      default_prepend                = output.value.default_prepend
      filter_chain                   = output.value.filter_chain
      filter_select                  = output.value.filter_select
      keep_sent_attributes           = output.value.keep_sent_attributes
      network                        = output.value.network
      no_client_to_client_reflection = output.value.no_client_to_client_reflection
      no_early_cut                   = output.value.no_early_cut
      redistribute                   = output.value.redistribute
      remove_private_as              = output.value.remove_private_as
    }
  }

  remote {
    address    = each.value.remote.address
    allowed_as = try(each.value.remote.allowed_as, null)
    as         = try(each.value.remote.as, null)
    port       = try(each.value.remote.port, null)
    ttl        = try(each.value.remote.ttl, null)
  }

  depends_on = [
    routeros_routing_filter_rule.routing_filter_rule,
  ]
}
