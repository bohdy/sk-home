// Keep provider credentials and transport settings driven by variables so the
// module can reuse the repo's external secret-management flow.
provider "routeros" {
  alias    = "gw"
  hosturl  = var.mikrotik_gw_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password
  insecure = var.mikrotik_insecure
}
