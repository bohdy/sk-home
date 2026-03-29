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

output "namespace_name" {
  description = "Namespace that owns the Tailscale subnet router objects."
  value       = kubernetes_namespace_v1.tailscale.metadata[0].name
}

output "deployment_name" {
  description = "Deployment name for the Tailscale subnet router."
  value       = kubernetes_deployment_v1.tailscale.metadata[0].name
}
