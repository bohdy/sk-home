# The observability exporter uses its own identity so a compromise cannot reuse
# the cluster provisioning token or inherit mutation privileges from that user.
resource "proxmox_virtual_environment_user" "observability" {
  user_id = "observability@pve"
  comment = "Read-only observability exporters; managed by OpenTofu"
  enabled = true
}

# Keep token privileges separate from the user. Proxmox evaluates separated
# tokens as the intersection of user and token ACLs, so both receive only the
# same built-in read-only role at the root path.
resource "proxmox_user_token" "observability_exporter" {
  user_id               = proxmox_virtual_environment_user.observability.user_id
  token_name            = "exporter"
  comment               = "Kubernetes Proxmox exporter; managed by OpenTofu"
  privileges_separation = true
}

# The passwordless parent user supplies the upper half of the separated-token
# permission intersection; it has no independent credential used by workloads.
resource "proxmox_acl" "observability_user" {
  user_id   = proxmox_virtual_environment_user.observability.user_id
  role_id   = "PVEAuditor"
  path      = "/"
  propagate = true
}

# The token-specific half prevents this token from inheriting any future user
# privilege beyond the same built-in read-only PVEAuditor role.
resource "proxmox_acl" "observability_exporter" {
  token_id  = proxmox_user_token.observability_exporter.id
  role_id   = "PVEAuditor"
  path      = "/"
  propagate = true
}
