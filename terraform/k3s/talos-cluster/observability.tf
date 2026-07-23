# The observability exporter uses its own identity so a compromise cannot reuse
# the cluster provisioning token or inherit mutation privileges from that user.
resource "proxmox_virtual_environment_group" "observability" {
  group_id = "observability"
  comment  = "Read-only observability identities; managed by OpenTofu"

  # Provider 0.106.0 reads separately managed ACLs into this resource's
  # deprecated inline block. Ignore that projection so the dedicated ACL
  # resource remains authoritative and later applies cannot remove it.
  lifecycle {
    ignore_changes = [acl]
  }
}

resource "proxmox_virtual_environment_user" "observability" {
  user_id = "observability@pve"
  comment = "Read-only observability exporters; managed by OpenTofu"
  enabled = true
  groups  = [proxmox_virtual_environment_group.observability.group_id]
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

# Provider 0.106.0 recorded the parent-user ACL as present while Proxmox stored
# only the similarly prefixed token ACL. Forget that phantom state entry without
# issuing a delete that could remove the real token ACL.
removed {
  from = proxmox_acl.observability_user

  lifecycle {
    destroy = false
  }
}

# Group membership supplies the parent user's half of the separated-token
# permission intersection without colliding with the token's ACL identity.
resource "proxmox_acl" "observability_group" {
  group_id  = proxmox_virtual_environment_group.observability.group_id
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
