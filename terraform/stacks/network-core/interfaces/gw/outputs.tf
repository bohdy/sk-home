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
