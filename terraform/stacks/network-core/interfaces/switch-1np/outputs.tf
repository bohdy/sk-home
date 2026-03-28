# Expose the resolved stack context so the Switch 1NP interface root can be
# reviewed before operators point it at the live RouterOS device.
output "stack_context" {
  description = "Resolved root-module context for the Switch 1NP interfaces stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = module.interfaces.common_tags
  }
}

# Expose the managed switch endpoint without leaking credentials so operators
# can confirm the intended RouterOS device for this root.
output "mikrotik_device" {
  description = "Configured MikroTik Switch 1NP managed by the interfaces stack."
  value       = local.mikrotik_device
}

# Expose the committed bridge and interface inventory so local review can
# confirm the shape Terraform will apply without reading each variable block.
output "interface_inventory" {
  description = "Committed non-sensitive Switch 1NP interface inventory managed by the interfaces stack."
  value       = module.interfaces.interface_inventory
}
