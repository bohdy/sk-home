# Connect Terraform to the MikroTik gateway so bridge, VLAN, tunnel, and
# gateway interface resources bind to the intended RouterOS device explicitly.
provider "routeros" {
  hosturl  = var.mikrotik_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
