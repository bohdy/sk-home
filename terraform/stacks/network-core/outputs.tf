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
