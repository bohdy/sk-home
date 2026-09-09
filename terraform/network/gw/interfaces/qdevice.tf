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

// RouterOS 7.23 uses the native `list` field for container mounts, while the
// pinned provider sends its incompatible `name` field. Keep the desired
// records in OpenTofu state so the recovery workflow can reconcile the live
// objects without allowing the provider to emit the rejected payload.
resource "terraform_data" "qdevice_mounts" {
  count = var.qdevice.enabled ? 1 : 0

  # This is a state-only desired record. The production-gated recovery step
  # owns the native RouterOS mount rows because the pinned provider cannot
  # represent their RouterOS 7.23 `list` field.
  input = local.qdevice_mounts
}

// The container record deliberately uses RouterOS's native `mountlists` field
// and literal mount-list names. The provider's `mounts` serializer is kept out
// of the graph for the same RouterOS 7.23 compatibility reason as above.
resource "terraform_data" "qdevice_container" {
  count = var.qdevice.enabled ? 1 : 0

  input = {
    "remote-image"  = var.qdevice.image
    interface       = var.qdevice.interface_name
    "root-dir"      = var.qdevice.root_dir
    mountlists      = ["qnetd_authorized_keys", "qnetd_nssdb", "qnetd_ssh_host_keys"]
    "start-on-boot" = true
    logging         = true
    running         = true
    comment         = "Proxmox QDevice qnetd"
    network = {
      interface_name = var.qdevice.interface_name
      address        = var.qdevice.address
      gateway        = var.qdevice.gateway
      vlan_id        = var.qdevice.vlan_id
      bridge         = routeros_interface_bridge.bridge.name
      frame_types    = "admit-only-untagged-and-priority-tagged"
    }
    container_config = {
      layer_dir           = var.qdevice.layer_dir
      tmpdir              = var.qdevice.tmpdir
      authorized_key_path = "${var.qdevice.ssh_authorized_dir}/authorized_keys"
    }
  }

  # Keep the desired record behind the provider-managed prerequisites so a
  # normal targeted plan presents the same dependency order as recovery.
  depends_on = [
    routeros_container_config.qdevice,
    terraform_data.qdevice_mounts,
    routeros_interface_bridge_port.qdevice,
    routeros_interface_bridge_vlan.bridge_vlan,
    routeros_file.qdevice_authorized_keys,
  ]
}
