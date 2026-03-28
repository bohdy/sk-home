# Connect Terraform to the MikroTik gateway so bridge, VLAN, tunnel, and
# gateway interface resources bind to the intended RouterOS device explicitly.
provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Connect Terraform to Switch 1PP so physical interface descriptions can be
# managed in the same interface-focused stack.
provider "routeros" {
  alias    = "switch_1pp"
  hosturl  = var.mikrotik_switch_1pp_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}

# Connect Terraform to Switch 1NP so physical interface descriptions can be
# managed alongside the gateway's interface inventory.
provider "routeros" {
  alias    = "switch_1np"
  hosturl  = var.mikrotik_switch_1np_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
