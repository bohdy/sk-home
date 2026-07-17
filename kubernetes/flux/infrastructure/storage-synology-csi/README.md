# Synology CSI Storage

This component installs Synology CSI as a generic cluster storage capability. It is intentionally not tied to observability or any other workload stack.

## Secret

The driver expects a Kubernetes Secret named `client-info-secret` in the `synology-csi` namespace. The secret must contain a `client-info.yml` key with DSM connection details.

Bitwarden Secrets Manager item `SK-TALOS-SYNO-CSI` contains only the password for the dedicated `synology-csi` DSM account. The non-secret host, port, HTTPS, and username settings remain documented configuration rather than being embedded in the Bitwarden value.

Create the complete client file from the Bitwarden-sourced password without printing either value, then create the Kubernetes Secret from that temporary file:

```bash
export SYNOLOGY_CSI_PASSWORD="$(bws secret get 3c76c84f-2fec-455c-b212-b46e00f63952 -o json | jq -r .value)"

jq -n --arg password "${SYNOLOGY_CSI_PASSWORD}" \
  '{clients: [{host: "10.1.100.10", port: 5001, https: true, username: "synology-csi", password: $password}]}' \
  > /tmp/synology-client-info.yml

kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace synology-csi --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n synology-csi create secret generic client-info-secret --from-file=client-info.yml=/tmp/synology-client-info.yml --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

unset SYNOLOGY_CSI_PASSWORD
rm -f /tmp/synology-client-info.yml
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

Do not commit the file, paste the password into shell history, or enable shell tracing while creating the secret. Restart the controller StatefulSet and node DaemonSet after changing the Secret because the driver reads the client configuration during startup.

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

The full lifecycle was validated successfully on 2026-07-17:

1. All controller and node CSI pods ran and registered on the four deterministic Talos node names.
2. A 1 GiB `synology-iscsi-retain` claim provisioned and mounted on `sk-talos-worker-1`.
3. A non-root pod wrote a marker using `fsGroup` ownership.
4. Same-node pod recreation preserved the marker.
5. Cross-node recreation on `sk-talos-cp-1` detached, reattached, and preserved the marker.
6. Online expansion to 2 GiB grew both the claim and mounted ext4 filesystem.
7. Claim deletion left PV `pvc-c18327d7-51df-451f-80ac-daac0c4bb6dc` in `Released` with `Retain`; Synology volume handle `678dcb5b-8eea-4688-8782-42f604b4ad7b` remains for explicit administrative cleanup.

The dedicated DSM account must be able to use the required storage and SAN Manager APIs and must not require 2-factor authentication, which this CSI driver cannot supply. DSM login error `403` indicates a second factor is required, while API error `105` indicates insufficient privileges.

Snapshots, NFS, SMB, and a `Delete` reclaim class are deferred until this core iSCSI path is proven.
