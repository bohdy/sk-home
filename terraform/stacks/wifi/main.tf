# Build a reusable stack context for UniFi wireless resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project            = var.project_name
      environment        = var.environment
      wireless_site_name = var.wireless_site_name
      stack              = "wifi"
      managed_by         = "terraform"
    },
    var.additional_tags
  )
}
