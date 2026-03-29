locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.observability_site_name
      stack       = "observability"
      managed_by  = "terraform"
    },
    var.additional_tags
  )
}
