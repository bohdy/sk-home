# Build a reusable stack context for Tailscale and overlay-network resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project      = var.project_name
      environment  = var.environment
      tailnet_name = var.tailnet_name
      stack        = "overlay"
      managed_by   = "terraform"
    },
    var.additional_tags
  )
}
