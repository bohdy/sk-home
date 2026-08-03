# Proxmox Exporter

This component deploys Prometheus PVE Exporter 3.8.2 as one stateless, ClusterIP-only replica. It collects cluster and node data every 30 seconds from `pve.bohdal.name`, which split DNS resolves to `10.1.100.201`, and exposes separate process metrics for exporter self-monitoring.

The pod maps the static API address to its certificate-valid hostname in `/etc/hosts` because the built-in Kubernetes resolver intentionally serves cluster discovery instead of the LAN split-DNS view. Its Cilium policy therefore needs no DNS permission and permits only HTTPS to `10.1.100.201:8006`; the exporter does not require Kubernetes service-name resolution. Keep this mapping and the split-DNS record aligned if the Proxmox address changes.

OpenTofu owns passwordless user `observability@pve` in dedicated group `observability`, its privilege-separated `exporter` token, and matching propagated `PVEAuditor` ACLs at `/` for the group and token. The token's effective permission is their read-only intersection. Bitwarden item `SK-TALOS-PROXMOX-EXPORTER-API-TOKEN` (`2ea66873-6852-4af9-bca2-b48f00f84a0a`) contains exactly the full `observability@pve!exporter=<secret>` token. The exporter splits that atomic value only in process memory; pod arguments, manifests, and files never contain credential material.

Bootstrap the namespace Secret without printing or writing the token to disk:

```sh
set +x
export PROXMOX_EXPORTER_API_TOKEN="$(bws secret get 2ea66873-6852-4af9-bca2-b48f00f84a0a -o json | jq -r .value)"

kubectl -n observability create secret generic proxmox-exporter-auth \
  --from-literal=api-token="${PROXMOX_EXPORTER_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

unset PROXMOX_EXPORTER_API_TOKEN
```

Proxmox serves one browser-trusted ACME certificate for canonical hostname `pve.bohdal.name` and compatibility alias `pve.sk.bohdal.name`. `PVE_VERIFY_SSL=true` keeps TLS verification enabled through the image's system trust store; do not reintroduce a private-CA override unless the management endpoint intentionally stops using a publicly trusted certificate.

## Validation

Render and validate the component:

```sh
kubectl kustomize kubernetes/flux/observability/proxmox
kubectl kustomize kubernetes/flux/observability/proxmox | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require a Ready pod with no repeated restarts, `up=1` for both the self-scrape and Proxmox scrape, successful TLS verification, stable `cluster="sk-talos"`, `site="sk"`, and `instance="pve"` labels, expected node, guest, storage, and backup metric families, bounded series counts, and no credential values in pod arguments, rendered manifests, logs, or metrics.

Routine rollback suspends or reverts `observability-proxmox`. The external Secret may remain for redeployment, but delete it explicitly if Proxmox monitoring is abandoned.
