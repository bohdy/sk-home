# Expose the resolved stack context so the routing root can be validated as one
# complete source of truth for gateway routing and BGP resources.
output "stack_context" {
  description = "Resolved root-module context for the nested routing stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}

# Expose the committed IPv4 route inventory so operators can confirm the
# intended gateway route set without opening the tfvars file directly.
output "ipv4_static_routes" {
  description = "IPv4 static routes declared for the MikroTik gateway."
  value = {
    for name, route in local.ipv4_static_routes :
    name => {
      dst_address   = route.dst_address
      routing_table = route.routing_table
      distance      = route.distance
      disabled      = route.disabled
      blackhole     = route.blackhole
      comment       = try(route.comment, null)
    }
  }
}

# Expose the committed BGP instance inventory so operators can confirm shared
# routing identity without opening the tfvars file directly.
output "bgp_instances" {
  description = "BGP instances declared for the MikroTik gateway."
  value = {
    for name, instance in local.bgp_instances :
    name => {
      as            = instance.as
      disabled      = instance.disabled
      router_id     = try(instance.router_id, null)
      routing_table = instance.routing_table
      vrf           = instance.vrf
      comment       = try(instance.comment, null)
    }
  }
}

# Expose the committed BGP template inventory so operators can review shared
# template inheritance without opening the tfvars file directly.
output "bgp_templates" {
  description = "BGP templates declared for the MikroTik gateway."
  value = {
    for name, template in local.bgp_templates :
    name => {
      as               = template.as
      disabled         = template.disabled
      multihop         = try(template.multihop, null)
      routing_table    = template.routing_table
      templates        = length(template.templates) == 0 ? [] : sort(tolist(template.templates))
      address_families = try(template.address_families, null)
      add_path_out     = try(template.add_path_out, null)
      keepalive_time   = try(template.keepalive_time, null)
      hold_time        = try(template.hold_time, null)
      nexthop_choice   = try(template.nexthop_choice, null)
      save_to          = try(template.save_to, null)
      use_bfd          = try(template.use_bfd, null)
      vrf              = template.vrf
      comment          = try(template.comment, null)
    }
  }
}

# Expose the committed BGP connection inventory so operators can confirm peer
# session intent and export policy without opening the tfvars file directly.
output "bgp_connections" {
  description = "BGP connections declared for the MikroTik gateway."
  value = {
    for name, connection in local.bgp_connections :
    name => {
      as               = connection.as
      disabled         = connection.disabled
      instance         = try(connection.instance, null)
      routing_table    = connection.routing_table
      vrf              = connection.vrf
      address_families = try(connection.address_families, null)
      connect          = try(connection.connect, null)
      multihop         = try(connection.multihop, null)
      templates        = length(connection.templates) == 0 ? [] : sort(tolist(connection.templates))
      comment          = try(connection.comment, null)
      local            = connection.local
      output           = try(connection.output, null)
      remote           = connection.remote
    }
  }
}

# Expose the committed routing filter inventory so operators can confirm BGP
# export policy intent without opening the tfvars file directly.
output "routing_filter_rules" {
  description = "Routing filter rules declared for the MikroTik gateway."
  value = {
    for name, rule in local.routing_filter_rules :
    name => {
      chain    = rule.chain
      disabled = rule.disabled
      rule     = rule.rule
      comment  = try(rule.comment, null)
    }
  }
}

# Expose the committed IPv6 route inventory so operators can confirm the
# intended gateway route set without opening the tfvars file directly.
output "ipv6_static_routes" {
  description = "IPv6 static routes declared for the MikroTik gateway."
  value = {
    for name, route in local.ipv6_static_routes :
    name => {
      dst_address   = route.dst_address
      routing_table = route.routing_table
      distance      = route.distance
      disabled      = route.disabled
      blackhole     = route.blackhole
      comment       = try(route.comment, null)
    }
  }
}
