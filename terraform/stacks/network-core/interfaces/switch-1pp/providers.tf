# Connect Terraform to Switch 1PP so imported bridge, VLAN, and physical
# interface resources bind to the intended RouterOS device explicitly.
provider "routeros" {
  hosturl  = var.mikrotik_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
