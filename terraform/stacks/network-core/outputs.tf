# Expose the resolved stack context so the bootstrap can be validated before
# MikroTik resources are added.
output "stack_context" {
  description = "Resolved root-module context for the network-core stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}

# Expose the managed device inventory without leaking credentials so future
# modules and operators can confirm the intended RouterOS endpoints.
output "mikrotik_devices" {
  description = "Configured MikroTik devices managed by the network-core stack."
  value       = local.mikrotik_devices
}

# Expose the declared DHCP scope inventory so operators can confirm the desired
# gateway-served DHCP layout directly from Terraform outputs.
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
    }
  }
}
