# This file is the reviewed, non-secret source of truth for the shared storage
# identities. Credentials are injected only by the trusted apply workflow.
storage_contract = {
  proxmox = {
    api_node     = "pve"
    cluster_name = "sk-home"
    nodes        = ["pve", "pve02"]

    storages = {
      iscsi = {
        id      = "iscsi-syno-v4"
        type    = "iscsi"
        portal  = "10.1.100.10"
        target  = "iqn.2000-01.com.synology:sknas.Target-1.0ea0c9a0f02"
        content = ["none"]
        nodes   = null
      }

      lvm = {
        id           = "lvm-iscsi-syno-v4"
        type         = "lvm"
        volume_group = "vg_syno"
        base         = "iscsi-syno-v4:0.0.1.scsi-360014054ad3c13ed6589d48d3dac84de"
        content      = ["rootdir", "images"]
        saferemove   = 0
        shared       = true
        nodes        = null
      }

      local_lvm = {
        id           = "local-lvm"
        type         = "lvmthin"
        volume_group = "pve"
        thin_pool    = "data"
        content      = ["rootdir", "images"]
        nodes        = ["pve"]
      }
    }
  }

  synology = {
    endpoint            = "https://nas.bohdal.name:5001"
    target_id           = "1"
    target_name         = "pve"
    target_iqn          = "iqn.2000-01.com.synology:sknas.Target-1.0ea0c9a0f02"
    target_max_sessions = 0
    host_id             = "2"
    lun_uuid            = "4ad3c13e-6589-48d3-ac84-e6b29c4c1302"
    initiator_iqns = [
      "iqn.1993-08.org.debian:01:c950a1e3add3",
      "iqn.1993-08.org.debian:01:d2bf225e1130",
    ]
    permission = "rw"
  }
}
