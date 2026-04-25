provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
