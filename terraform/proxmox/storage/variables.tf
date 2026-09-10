variable "storage_contract" {
  # Keep non-secret storage identity in reviewed repository configuration. The
  # trusted workflow supplies only the credentials needed to reconcile it.
  description = "Desired shared Proxmox and Synology iSCSI storage contract."
  type = object({
    proxmox = object({
      api_node     = string
      cluster_name = string
      nodes        = set(string)
      storages = object({
        iscsi = object({
          id      = string
          type    = string
          portal  = string
          target  = string
          content = set(string)
          nodes   = optional(set(string))
        })
        lvm = object({
          id           = string
          type         = string
          volume_group = string
          base         = string
          content      = set(string)
          saferemove   = number
          shared       = bool
          nodes        = optional(set(string))
        })
        local_lvm = object({
          id           = string
          type         = string
          volume_group = string
          thin_pool    = string
          content      = set(string)
          nodes        = set(string)
        })
      })
    })
    synology = object({
      endpoint            = string
      target_id           = string
      target_name         = string
      target_iqn          = string
      target_max_sessions = number
      host_id             = string
      lun_uuid            = string
      initiator_iqns      = set(string)
      permission          = string
    })
  })

  validation {
    condition = (
      var.storage_contract.proxmox.cluster_name == "sk-home"
      && var.storage_contract.proxmox.api_node == "pve"
      && var.storage_contract.proxmox.nodes == toset(["pve", "pve02"])
      && var.storage_contract.proxmox.storages.iscsi.type == "iscsi"
      && var.storage_contract.proxmox.storages.lvm.type == "lvm"
      && var.storage_contract.proxmox.storages.local_lvm.type == "lvmthin"
      && var.storage_contract.synology.target_max_sessions == 0
      && var.storage_contract.synology.permission == "rw"
      && length(var.storage_contract.synology.initiator_iqns) == 2
    )
    error_message = "The shared storage contract must describe the two-node sk-home cluster and unlimited read/write iSCSI access."
  }

  validation {
    condition = alltrue([
      for iqn in var.storage_contract.synology.initiator_iqns : can(regex("^iqn\\.[^[:space:]]+$", iqn))
    ])
    error_message = "Every Synology initiator identity must be a non-empty iSCSI qualified name."
  }
}
