# Connect Terraform to the MikroTik gateway using a dedicated provider alias so
# router resources can target the correct device explicitly.
provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Connect Terraform to the MikroTik Switch 1PP with its own provider alias so
# switch resources stay isolated from the gateway configuration.
provider "routeros" {
  alias    = "switch_1pp"
  hosturl  = var.mikrotik_switch_1pp_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Connect Terraform to the MikroTik Switch 1NP with its own provider alias so
# future resources can be bound to that device directly.
provider "routeros" {
  alias    = "switch_1np"
  hosturl  = var.mikrotik_switch_1np_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
