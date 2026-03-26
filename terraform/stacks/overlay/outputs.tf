# Expose the resolved stack context so the bootstrap can be validated before
# Tailscale resources are added.
output "stack_context" {
  description = "Resolved root-module context for the overlay stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    tailnet_name = var.tailnet_name
    common_tags  = local.common_tags
  }
}
