# Build a reusable stack context for Cloudflare edge identity resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project       = var.project_name
      environment   = var.environment
      access_domain = var.access_domain
      stack         = "identity-edge"
      managed_by    = "terraform"
    },
    var.additional_tags
  )
}
