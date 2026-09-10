# Proxmox shared iSCSI storage

This stack records and reconciles the shared Synology iSCSI storage contract used by the two-node `sk-home` Proxmox cluster. It exists separately from the Talos VM stack because storage access changes have a different failure and rollback boundary.

## Desired state

The committed `storage.auto.tfvars` declares the existing Synology target, its mapped LUN, both Proxmox initiator IQNs, and the shared Proxmox `iscsi-syno-v4` and `lvm-iscsi-syno-v4` entries. It also scopes the node-local `local-lvm` storage to `pve`; `pve02` does not have the `pve/data` thin pool.

The shared LVM entry deliberately retains the iSCSI `base` device. It is a shared block-storage backend for VM and container disks, not a clustered filesystem. Do not mount the same filesystem read/write from multiple guests or use this storage as a generic `ReadWriteMany` volume.

## Provider boundary

The pinned `bpg/proxmox` provider can describe ordinary LVM storage, but its storage resources do not expose Proxmox's iSCSI storage type or the LVM `base` field needed for remote iSCSI. The repository therefore stores the reviewed desired values in two `terraform_data` records and uses `scripts/proxmox-synology-storage-reconcile.sh` only from the trusted production workflow. This is a documented break-glass boundary, not an invitation to edit `/etc/pve/storage.cfg` by hand.

The trusted workflow connects to Proxmox as `pve.sk.bohdal.name` and Synology as `nas.bohdal.name` with normal certificate verification. A valid, trusted Synology HTTPS certificate is required before either live preflight or production apply; renew or otherwise repair the currently identified certificate issue before dispatching the storage path, and do not restore an `--insecure` option.

The reconciler can create the declared Proxmox storage entries when they are absent, update only their declared content, shared, node-scope, and saferemove fields, and refuses identity mismatches and all deletes. On Synology it may set the target's session limit and add the two declared initiators; it never deletes targets, unmaps LUNs, removes initiators, or changes an unexpected ACL.

## Workflow

Pull requests run `tofu init -backend=false` and `tofu validate` without infrastructure credentials or binary plans. An optional review-only dispatch performs a read-only live preflight and produces an informational `proxmox-storage-tofuplan` artifact; that artifact is not reusable by a later dispatch. The production procedure is one `apply_proxmox_storage` dispatch from `main`: the same run creates and guards its immutable artifact, publishes a plan summary and digest, waits for the `production` environment, verifies the downloaded artifact digest, applies that exact artifact, reconciles the two APIs, and verifies both Proxmox nodes have active shared storage and both initiators are connected.

The exact dispatch flags are documented in the root README. For an apply dispatch, review the plan summary and `proxmox-storage-tofuplan` artifact from that same run before approving the production environment; confirm that it contains only the two storage contract records and no delete or replacement actions. Do not treat an artifact from a separate plan-only run as approval for a later apply run. If verification fails, stop and inspect the live target, ACL, iSCSI sessions, and Proxmox storage status before generating a new plan.

## Network and rollback

Both Proxmox nodes and the Synology target use the existing management VLAN 100 reachability. This stack adds no RouterOS interfaces, VLAN rows, routes, or firewall rules, so the infrastructure review reports an explicit firewall no-change result and the storage workflow does not require a firewall rule or inventory artifact. Review a fresh firewall inventory separately if operational assurance is needed.

The reconciler has no destructive rollback path. If post-apply verification fails, stop rather than retrying the same artifact; inspect the live target, ACL, iSCSI sessions, and Proxmox storage status, then correct the contract and create a new reviewed plan. Roll back the repository contract only after the live storage users are migrated and a separate review explicitly covers any target, LUN, or storage removal. Never remove the mapped LUN or shared storage entry as part of an ordinary application rollback.
