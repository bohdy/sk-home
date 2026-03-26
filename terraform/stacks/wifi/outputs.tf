# Expose the resolved stack context so the bootstrap can be validated before
# UniFi resources are added.
output "stack_context" {
  description = "Resolved root-module context for the wifi stack."
  value = {
    project_name       = var.project_name
    environment        = var.environment
    wireless_site_name = var.wireless_site_name
    common_tags        = local.common_tags
  }
}
