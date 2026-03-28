# Expose the resolved stack context so the DHCP root can be validated before
# additional gateway resources are added.
output "stack_context" {
  description = "Resolved root-module context for the nested DHCP stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}

# Expose the committed DHCP scope inventory so operators can confirm the
# intended gateway-served network layout from Terraform outputs.
output "dhcp_scopes" {
  description = "DHCP scopes declared for the MikroTik gateway."
  value = {
    for name, scope in local.dhcp_scopes :
    name => {
      interface   = scope.interface
      pool_name   = scope.pool_name
      subnet      = scope.subnet
      gateway     = scope.gateway
      dns_servers = scope.dns_servers
      domain      = try(scope.domain, null)
      lease_time  = scope.lease_time
      add_arp     = scope.add_arp
      option_set  = try(scope.option_set, null)
    }
  }
}

# Expose the committed reservation map so operators can verify static lease
# intent without opening the tfvars file directly.
output "dhcp_reservations" {
  description = "Static DHCP reservations declared for the MikroTik gateway."
  value = {
    for name, reservation in local.dhcp_reservations :
    name => {
      server      = reservation.server
      address     = reservation.address
      mac_address = reservation.mac_address
      comment     = try(reservation.comment, null)
    }
  }
}

# Expose the declared option-set inventory so operators can confirm which DHCP
# vendor options are expected on each scope.
output "dhcp_option_sets" {
  description = "DHCP option sets declared for the MikroTik gateway."
  value = {
    for name, option_set in var.dhcp_option_sets :
    name => {
      name    = option_set.name
      options = option_set.options
    }
  }
}
