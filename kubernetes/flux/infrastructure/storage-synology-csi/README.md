# Synology CSI Storage

This component installs Synology CSI as a generic cluster storage capability. It is intentionally not tied to observability or any other workload stack.

## Secret

The driver expects a Kubernetes Secret named `client-info-secret` in the `synology-csi` namespace. The secret must contain a `client-info.yml` key with DSM connection details.

Create the secret from a local file or Bitwarden-sourced temporary file without printing the contents:

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace synology-csi --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n synology-csi create secret generic client-info-secret --from-file=client-info.yml=/path/to/client-info.yml --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
```

The `client-info.yml` file has this shape:

```yaml
clients:
  - host: 10.1.x.y
    port: 5001
    https: true
    username: synology-csi
    password: replace-with-bitwarden-value
```

Do not commit the file, paste the password into shell history, or enable shell tracing while creating the secret.

## StorageClass

The first class is `synology-iscsi-retain`:

- non-default and explicit-only
- iSCSI protocol
- `ReadWriteOnce` workload expectation
- `ext4` filesystem
- `Retain` reclaim policy
- `WaitForFirstConsumer` binding
- volume expansion enabled

The StorageClass intentionally does not set a DSM IP or volume location. The CSI driver chooses from the DSM clients configured in `client-info.yml`; pinning a DSM or `/volumeN` can be added later after the first validation pass if we need stricter placement.

## Validation

Before production workloads use this class, validate the full lifecycle:

1. Confirm all CSI pods are running.
2. Create a test PVC using `synology-iscsi-retain`.
3. Mount it in a single pod and write a test file.
4. Recreate the pod on the same node and confirm the file remains.
5. Force a cross-node recreate and confirm detach, attach, and data persistence.
6. Expand the PVC and confirm the filesystem grows.
7. Delete the PVC and confirm the retained PV and DSM LUN are not destroyed automatically.

Snapshots, NFS, SMB, and a `Delete` reclaim class are deferred until this core iSCSI path is proven.
