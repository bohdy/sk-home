# tflint-ignore-file: terraform_unused_declarations

# Keep the legacy RouterOS gateway provider available in the parent root until
# DHCP resources have been migrated out of the old state.
provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Keep the legacy Switch 1PP provider available in the parent root until
# existing state no longer requires the original provider wiring.
provider "routeros" {
  alias    = "switch_1pp"
  hosturl  = var.mikrotik_switch_1pp_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Keep the legacy Switch 1NP provider available in the parent root until
# existing state no longer requires the original provider wiring.
provider "routeros" {
  alias    = "switch_1np"
  hosturl  = var.mikrotik_switch_1np_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
