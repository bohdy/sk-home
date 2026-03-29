output "stack_context" {
  description = "Resolved root-module context for the observability stack."
  value = {
    project_name            = var.project_name
    environment             = var.environment
    observability_site_name = var.observability_site_name
    common_tags             = local.common_tags
  }
}
