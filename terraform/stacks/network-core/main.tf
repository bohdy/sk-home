# Build a reusable stack context for router and switch resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "network-core"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Keep device endpoint metadata in one place so resources and outputs can
  # refer to the managed MikroTik inventory consistently.
  mikrotik_devices = {
    gw = {
      name    = "GW"
      hosturl = var.mikrotik_gw_hosturl
      role    = "gateway"
    }
    switch_1pp = {
      name    = "Switch 1PP"
      hosturl = var.mikrotik_switch_1pp_hosturl
      role    = "switch"
    }
    switch_1np = {
      name    = "Switch 1NP"
      hosturl = var.mikrotik_switch_1np_hosturl
      role    = "switch"
    }
  }
}
