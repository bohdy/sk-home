# Proxmox Exporter

This component deploys Prometheus PVE Exporter 3.8.2 as one stateless, ClusterIP-only replica. It collects cluster and node data every 30 seconds from `pve.sk.bohdal.name`, which split DNS resolves to `10.1.100.201`, and exposes separate process metrics for exporter self-monitoring.

OpenTofu owns passwordless user `observability@pve`, its privilege-separated `exporter` token, and matching propagated `PVEAuditor` ACLs at `/` for both identities. The token's effective permission is their read-only intersection. Bitwarden item `SK-TALOS-PROXMOX-EXPORTER-API-TOKEN` (`2ea66873-6852-4af9-bca2-b48f00f84a0a`) contains exactly the full `observability@pve!exporter=<secret>` token. The exporter splits that atomic value only in process memory; pod arguments, manifests, and files never contain credential material.

Bootstrap the namespace Secret without printing or writing the token to disk:

```sh
set +x
export PROXMOX_EXPORTER_API_TOKEN="$(bws secret get 2ea66873-6852-4af9-bca2-b48f00f84a0a -o json | jq -r .value)"

kubectl -n observability create secret generic proxmox-exporter-auth \
  --from-literal=api-token="${PROXMOX_EXPORTER_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

unset PROXMOX_EXPORTER_API_TOKEN
```

The committed public Proxmox cluster CA has SHA-256 fingerprint `9B:01:0B:A0:FD:A6:91:18:00:72:18:D0:0F:94:AB:CE:2F:95:08:6E:A5:FF:20:10:57:23:C7:28:C0:59:EC:98` and expires on 2035-08-14. `REQUESTS_CA_BUNDLE` keeps certificate verification enabled against the certificate-valid internal name. Rotate the committed CA and verify its fingerprint before the Proxmox cluster CA expires or changes.

## Validation

Render and validate the component:

```sh
kubectl kustomize kubernetes/flux/observability/proxmox
kubectl kustomize kubernetes/flux/observability/proxmox | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require a Ready pod with no repeated restarts, `up=1` for both the self-scrape and Proxmox scrape, successful TLS verification, stable `cluster="sk-talos"`, `site="sk"`, and `instance="pve"` labels, expected node, guest, storage, and backup metric families, bounded series counts, and no credential values in pod arguments, rendered manifests, logs, or metrics.

Routine rollback suspends or reverts `observability-proxmox`. The external Secret may remain for redeployment, but delete it explicitly if Proxmox monitoring is abandoned.
