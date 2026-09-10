locals {
  # Normalize sets to sorted lists before storing the contract. This keeps the
  # state and generated immutable plan stable when HCL collection ordering
  # changes without changing the desired storage identity.
  proxmox_contract = {
    api_node     = var.storage_contract.proxmox.api_node
    cluster_name = var.storage_contract.proxmox.cluster_name
    nodes        = sort(tolist(var.storage_contract.proxmox.nodes))
    storages = {
      iscsi = {
        id      = var.storage_contract.proxmox.storages.iscsi.id
        type    = var.storage_contract.proxmox.storages.iscsi.type
        portal  = var.storage_contract.proxmox.storages.iscsi.portal
        target  = var.storage_contract.proxmox.storages.iscsi.target
        content = sort(tolist(var.storage_contract.proxmox.storages.iscsi.content))
        nodes   = var.storage_contract.proxmox.storages.iscsi.nodes == null ? null : sort(tolist(var.storage_contract.proxmox.storages.iscsi.nodes))
      }
      lvm = {
        id           = var.storage_contract.proxmox.storages.lvm.id
        type         = var.storage_contract.proxmox.storages.lvm.type
        volume_group = var.storage_contract.proxmox.storages.lvm.volume_group
        base         = var.storage_contract.proxmox.storages.lvm.base
        content      = sort(tolist(var.storage_contract.proxmox.storages.lvm.content))
        saferemove   = var.storage_contract.proxmox.storages.lvm.saferemove
        shared       = var.storage_contract.proxmox.storages.lvm.shared
        nodes        = var.storage_contract.proxmox.storages.lvm.nodes == null ? null : sort(tolist(var.storage_contract.proxmox.storages.lvm.nodes))
      }
      local_lvm = {
        id           = var.storage_contract.proxmox.storages.local_lvm.id
        type         = var.storage_contract.proxmox.storages.local_lvm.type
        volume_group = var.storage_contract.proxmox.storages.local_lvm.volume_group
        thin_pool    = var.storage_contract.proxmox.storages.local_lvm.thin_pool
        content      = sort(tolist(var.storage_contract.proxmox.storages.local_lvm.content))
        nodes        = sort(tolist(var.storage_contract.proxmox.storages.local_lvm.nodes))
      }
    }
  }

  # Synology's host and target APIs are not exposed by the pinned OpenTofu
  # providers in this repository. Store their reviewed, non-secret identity as
  # a separate contract so the trusted reconciler can adopt it safely.
  synology_contract = {
    endpoint            = var.storage_contract.synology.endpoint
    target_id           = var.storage_contract.synology.target_id
    target_name         = var.storage_contract.synology.target_name
    target_iqn          = var.storage_contract.synology.target_iqn
    target_max_sessions = var.storage_contract.synology.target_max_sessions
    host_id             = var.storage_contract.synology.host_id
    lun_uuid            = var.storage_contract.synology.lun_uuid
    initiator_iqns      = sort(tolist(var.storage_contract.synology.initiator_iqns))
    permission          = var.storage_contract.synology.permission
  }
}

# This is a state-only desired record. The production-gated workflow applies the
# immutable plan and then passes its reviewed values to the narrowly scoped API
# reconciler.
resource "terraform_data" "proxmox_storage_contract" {
  input = local.proxmox_contract

  lifecycle {
    precondition {
      condition     = length(local.proxmox_contract.nodes) == 2
      error_message = "The Proxmox storage contract must cover exactly pve and pve02."
    }
    precondition {
      condition     = local.proxmox_contract.storages.lvm.base != ""
      error_message = "The shared LVM storage must retain an explicit iSCSI base device."
    }
  }
}

# Keep the NAS access contract separate from Proxmox storage so a review can
# see exactly which external identity and LUN mapping the break-glass API path
# is allowed to touch.
resource "terraform_data" "synology_iscsi_contract" {
  input = local.synology_contract

  lifecycle {
    precondition {
      condition     = length(local.synology_contract.initiator_iqns) == 2
      error_message = "The Synology contract must contain both Proxmox initiator IQNs."
    }
    precondition {
      condition     = local.synology_contract.permission == "rw"
      error_message = "The Synology LUN ACL must remain read/write for Proxmox."
    }
  }
}
