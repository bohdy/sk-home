# Storage design

This file records the current design for generic Kubernetes persistent storage in the `sk-talos` cluster. Storage is a cluster infrastructure capability, not an observability-specific component, even though observability is the first known workload that depends on it.

## Goal

Provide a stable NAS-backed Kubernetes StorageClass for stateful single-writer workloads. The first implementation should let workloads opt in to persistent storage explicitly, validate iSCSI behavior on Talos before production use, and avoid broad shared-storage assumptions.

## Backend

The first storage backend is the existing Synology NAS, exposed to Kubernetes through Synology CSI.

Use the Sidero-documented Talos-specific Synology CSI path. That path requires Synology DSM 7.0 or newer, Kubernetes v1.20 or newer, the `siderolabs/iscsi-tools` Talos extension, Synology API credentials, a Talos-compatible Synology CSI image, and live PVC validation.

The Talos image schematic in `terraform/k3s/talos-cluster/image/schematic.yaml` includes `siderolabs/iscsi-tools`. Talos nodes must be rolled or updated onto that image before deploying the CSI driver.

## StorageClass

Create the first StorageClass as an explicit-only, non-default iSCSI class for `ReadWriteOnce` data volumes.

The intended StorageClass behavior is:

- Name: `synology-iscsi-retain`
- Protocol: iSCSI
- Filesystem: `ext4`
- Access pattern: `ReadWriteOnce`
- Reclaim policy: `Retain`
- Volume binding mode: `WaitForFirstConsumer`
- Volume expansion: enabled
- Default class: false

Do not make the first Synology StorageClass default. Workloads must set `storageClassName` deliberately until the driver and lifecycle behavior are proven boring.

Do not create a `Delete` reclaim-policy class in the first implementation. Add one later only for disposable workloads that explicitly accept automatic backing-volume deletion.

Reserve NFS for later `ReadWriteMany` or shared-file workloads. Do not use NFS for the first VictoriaMetrics, VictoriaLogs, or Grafana data volumes unless iSCSI validation fails and the tradeoff is revisited.

## Consumers

The first expected consumers are stateful single-writer workloads such as VictoriaMetrics, VictoriaLogs, and Grafana.

Collectors and exporters should normally stay ephemeral. Do not add shared NFS storage for collectors unless a specific component proves it needs durable shared files.

## Credentials

Bitwarden is the source of truth for Synology DSM credentials.

For the first live validation, it is acceptable to create the Kubernetes Secret manually from Bitwarden-sourced values. Do not commit DSM credentials, echo them in commands, print them in logs, or store them in generated artifacts.

Automate secret injection only after the CSI path itself is proven.

## Flux placement

Synology CSI should be a generic infrastructure component, not part of the observability component tree.

The intended Flux component is `storage-synology-csi`. It should depend on `cluster-policy` and Cilium. DNS and storage should be independent siblings; observability storage should depend on validated generic storage.

## Implementation order

1. Roll or update Talos nodes onto the iSCSI-capable image.
2. Deploy the Talos-compatible Synology CSI driver through Flux.
3. Create the explicit-only `synology-iscsi-retain` StorageClass.
4. Create the Synology CSI Kubernetes Secret from Bitwarden-sourced values.
5. Run live PVC validation before any dependent production workload uses the class.

## Validation

The StorageClass is not production-ready until a live validation proves the full volume lifecycle.

Required validation:

- Create a PVC using `synology-iscsi-retain`.
- Run a pod or job that mounts the PVC and writes test data.
- Delete and recreate the pod on the same node, then confirm the data remains.
- Move the workload to another Talos node, then confirm the iSCSI volume detaches, reattaches, mounts, and preserves data.
- Expand the PVC, then confirm the filesystem sees the new size.
- Delete the PVC, then confirm `Retain` preserves the backing Synology data/LUN as expected.

Validate Synology CSI snapshot capability if it is straightforward during bring-up, but do not make snapshot or backup automation part of v1.

## Exclusions

The first storage implementation does not include a default StorageClass, NFS, SMB, backup automation, snapshot automation, a disposable `Delete` class, or clustered filesystem semantics.

Do not design multi-node shared write access on iSCSI. iSCSI volumes are treated as RWO block storage for one writer at a time.
