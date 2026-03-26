# Expose the resolved stack context so the bootstrap can be validated before
# Cloudflare resources are added.
output "stack_context" {
  description = "Resolved root-module context for the identity-edge stack."
  value = {
    project_name  = var.project_name
    environment   = var.environment
    access_domain = var.access_domain
    common_tags   = local.common_tags
  }
}
