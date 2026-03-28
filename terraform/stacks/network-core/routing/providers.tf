# Connect Terraform to the MikroTik gateway using a dedicated provider alias so
# every routing resource is bound to the correct RouterOS device explicitly.
provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
