output "stack_context" {
  description = "Resolved root-module context for the Proxmox platform stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}
