# Expose the resolved stack context so the routing root can be validated before
# BGP resources are added later.
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
