# Run Corosync's qnetd quorum helper directly on the gateway only when the
# operator opts in. The veth is kept out of var.interfaces because that map is
# reserved for physical Ethernet resources and their existing memberships.
resource "routeros_interface_veth" "qdevice" {
  count    = var.qdevice.enabled ? 1 : 0
  provider = routeros.gw

  name    = var.qdevice.interface_name
  address = [var.qdevice.address]
  gateway = var.qdevice.gateway
  comment = "Proxmox QDevice qnetd"
}

# Attach qnetd as an access-style port on the management VLAN. Restricting
# ingress to untagged frames prevents a container from injecting VLAN tags.
resource "routeros_interface_bridge_port" "qdevice" {
  count    = var.qdevice.enabled ? 1 : 0
  provider = routeros.gw

  bridge      = routeros_interface_bridge.bridge.name
  interface   = routeros_interface_veth.qdevice[0].name
  pvid        = var.qdevice.vlan_id
  frame_types = "admit-only-untagged-and-priority-tagged"
  comment     = "Proxmox QDevice qnetd management access"
}

# RouterOS keeps container extraction on the external disk. The qnetd root
# directory and its persistent mount sources below are also USB-backed; the
# USB filesystem and parent directories are a non-destructive prerequisite.
resource "routeros_container_config" "qdevice" {
  count    = var.qdevice.enabled ? 1 : 0
  provider = routeros.gw

  # Keep the existing global registry selection untouched; the targeted
  # workflow validates that it already points at Docker Hub before planning.
  layer_dir = var.qdevice.layer_dir
  tmpdir    = var.qdevice.tmpdir

  # The registry URL is shared global state and is intentionally adopted but
  # not owned by this qdevice-specific resource.
  lifecycle {
    ignore_changes = [registry_url]
  }
}

# qnetd's SSH bootstrap accepts the Proxmox node public key and no password.
# Keep the key in the caller's protected variable/secret injection path rather
# than generating or retrieving key material from this module.
resource "routeros_file" "qdevice_authorized_keys" {
  count    = var.qdevice.enabled ? 1 : 0
  provider = routeros.gw

  name     = "${var.qdevice.ssh_authorized_dir}/authorized_keys"
  contents = "${trimspace(var.qdevice.ssh_public_key)}\n"
}

locals {
  # These mounts preserve qnetd's NSS database, SSH host identity, and
  # authorized-key file across container replacement and router reboot.
  qdevice_mounts = var.qdevice.enabled ? {
    qnetd_nssdb = {
      src = var.qdevice.nssdb_dir
      dst = "/etc/corosync/qnetd/nssdb"
    }
    qnetd_ssh_host_keys = {
      src = var.qdevice.ssh_host_keys_dir
      dst = "/etc/ssh/keys"
    }
    qnetd_authorized_keys = {
      src = var.qdevice.ssh_authorized_dir
      dst = "/root/.ssh"
    }
  } : {}
}

resource "routeros_container_mounts" "qdevice" {
  for_each = local.qdevice_mounts
  provider = routeros.gw

  name = each.key
  src  = each.value.src
  dst  = each.value.dst

  # The authorized_keys file must exist before the mounted SSH directory is
  # attached to the container.
  depends_on = [routeros_file.qdevice_authorized_keys]
}

# The image uses an explicit multi-architecture version tag; update it only as
# a deliberate change so image and SSH-bootstrap behavior remain reviewable.
resource "routeros_container" "qdevice" {
  count    = var.qdevice.enabled ? 1 : 0
  provider = routeros.gw

  remote_image  = var.qdevice.image
  interface     = routeros_interface_veth.qdevice[0].name
  root_dir      = var.qdevice.root_dir
  mounts        = [for mount in values(routeros_container_mounts.qdevice) : mount.name]
  start_on_boot = true
  logging       = true
  running       = true
  comment       = "Proxmox QDevice qnetd"

  # The explicit dependencies keep image extraction/startup behind the
  # network, global container config, authorized key, and persistent mounts.
  depends_on = [
    routeros_container_config.qdevice,
    routeros_container_mounts.qdevice,
    routeros_interface_bridge_port.qdevice,
    routeros_interface_bridge_vlan.bridge_vlan,
  ]
}
