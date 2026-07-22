# The observability exporter uses its own identity so a compromise cannot reuse
# the cluster provisioning token or inherit mutation privileges from that user.
resource "proxmox_virtual_environment_user" "observability" {
  user_id = "observability@pve"
  comment = "Read-only observability exporters; managed by OpenTofu"
  enabled = true
}

# Keep token privileges separate from the user. The explicit token ACL below is
# therefore the complete authorization boundary for exporter API requests.
resource "proxmox_user_token" "observability_exporter" {
  user_id               = proxmox_virtual_environment_user.observability.user_id
  token_name            = "exporter"
  comment               = "Kubernetes Proxmox exporter; managed by OpenTofu"
  privileges_separation = true
}

# PVEAuditor at the root is the built-in read-only role required to discover
# cluster, node, storage, and guest metrics without granting mutation rights.
resource "proxmox_acl" "observability_exporter" {
  token_id  = proxmox_user_token.observability_exporter.id
  role_id   = "PVEAuditor"
  path      = "/"
  propagate = true
}
