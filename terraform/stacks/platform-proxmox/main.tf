locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "platform-proxmox"
      managed_by  = "terraform"
    },
    var.additional_tags
  )
}
