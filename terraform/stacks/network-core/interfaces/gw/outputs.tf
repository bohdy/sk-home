# Expose the resolved stack context so the gateway interface root can be
# reviewed before operators point it at the live RouterOS device.
output "stack_context" {
  description = "Resolved root-module context for the gateway interfaces stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = module.interfaces.common_tags
  }
}

# Expose the managed gateway endpoint without leaking credentials so operators
# can confirm the intended RouterOS device for this root.
output "mikrotik_device" {
  description = "Configured MikroTik gateway managed by the interfaces stack."
  value       = local.mikrotik_device
}

# Expose the committed bridge and interface inventory so local review can
# confirm the shape Terraform will apply without reading each variable block.
output "interface_inventory" {
  description = "Committed non-sensitive gateway interface inventory managed by the interfaces stack."
  value       = module.interfaces.interface_inventory
}

# Expose committed IPv4 interface addresses in a stable, purpose-built output
# so other stacks can consume gateway L3 interface identity without parsing the
# full interface inventory payload.
output "ipv4_interface_addresses" {
  description = "IPv4 interface addresses declared for the gateway, keyed by logical address key."
  value = {
    for address_key, address in var.ipv4_interface_addresses :
    address_key => {
      interface = address.interface
      address   = address.address
      comment   = try(address.comment, null)
      disabled  = try(address.disabled, false)
      vrf       = try(address.vrf, null)
    }
  }
}

# Expose committed IPv6 interface addresses in a stable, purpose-built output
# so other stacks can consume dual-stack gateway interface identity directly.
output "ipv6_interface_addresses" {
  description = "IPv6 interface addresses declared for the gateway, keyed by logical address key."
  value = {
    for address_key, address in var.ipv6_interface_addresses :
    address_key => {
      interface       = address.interface
      address         = address.address
      comment         = try(address.comment, null)
      disabled        = try(address.disabled, false)
      advertise       = try(address.advertise, null)
      auto_link_local = try(address.auto_link_local, null)
      eui_64          = try(address.eui_64, null)
      from_pool       = try(address.from_pool, null)
      no_dad          = try(address.no_dad, null)
    }
  }
}

# Expose IPv4 addresses grouped by interface so downstream stacks can reference
# all configured addresses for a given gateway interface without filtering.
output "ipv4_addresses_by_interface" {
  description = "IPv4 gateway interface addresses grouped by interface name."
  value = {
    for interface_name in sort(distinct([
      for address in values(var.ipv4_interface_addresses) : address.interface
    ])) :
    interface_name => [
      for address_key in sort(keys(var.ipv4_interface_addresses)) : {
        key      = address_key
        address  = var.ipv4_interface_addresses[address_key].address
        comment  = try(var.ipv4_interface_addresses[address_key].comment, null)
        disabled = try(var.ipv4_interface_addresses[address_key].disabled, false)
        vrf      = try(var.ipv4_interface_addresses[address_key].vrf, null)
      } if var.ipv4_interface_addresses[address_key].interface == interface_name
    ]
  }
}

# Expose IPv6 addresses grouped by interface so downstream stacks can reference
# all configured addresses for a given gateway interface without filtering.
output "ipv6_addresses_by_interface" {
  description = "IPv6 gateway interface addresses grouped by interface name."
  value = {
    for interface_name in sort(distinct([
      for address in values(var.ipv6_interface_addresses) : address.interface
    ])) :
    interface_name => [
      for address_key in sort(keys(var.ipv6_interface_addresses)) : {
        key             = address_key
        address         = var.ipv6_interface_addresses[address_key].address
        comment         = try(var.ipv6_interface_addresses[address_key].comment, null)
        disabled        = try(var.ipv6_interface_addresses[address_key].disabled, false)
        advertise       = try(var.ipv6_interface_addresses[address_key].advertise, null)
        auto_link_local = try(var.ipv6_interface_addresses[address_key].auto_link_local, null)
        eui_64          = try(var.ipv6_interface_addresses[address_key].eui_64, null)
        from_pool       = try(var.ipv6_interface_addresses[address_key].from_pool, null)
        no_dad          = try(var.ipv6_interface_addresses[address_key].no_dad, null)
      } if var.ipv6_interface_addresses[address_key].interface == interface_name
    ]
  }
}
