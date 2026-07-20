# SNMP Exporter

This component defines Prometheus SNMP Exporter 0.30.1 as a reusable, ClusterIP-only multi-target collector. It is intentionally not added to the cluster Flux tree until the target inventory and external credential Secret are complete.

## Configuration

`generator.yml` selects the reviewed upstream `system`, `if_mib`, `mikrotik`, `synology`, `apcups`, `ups_mib`, `printer_mib`, and `ubiquiti_unifi` modules. `snmp.yml` is the corresponding generated runtime configuration. Both files are extracted from the official Prometheus SNMP Exporter v0.30.1 generator input and generated configuration without changing module content.

The authoritative source snapshot is the upstream `v0.30.1` tag. Its generator Makefile retrieves the selected modules' MIBs from:

- Net-SNMP v5.9 and IANA registries for standard system, interface, and printer types
- MikroTik RouterOS 7.18.2 for `MIKROTIK-MIB`
- Synology's DSM developer MIB archive
- Prometheus Community's APC `PowerNet-MIB`
- Printer Working Group's RFC 3805 printer MIB
- Ubiquiti's `UBNT-UniFi-MIB` download
- Observium's generic `UPS-MIB` source

Several vendor URLs are unversioned upstream. Treat the committed generated output and the SNMP Exporter v0.30.1 tag as the reproducible review boundary. Do not commit downloaded MIB files unless their redistribution licenses explicitly permit it.

The committed auth definitions contain environment-variable placeholders rather than credentials. `snmp_v2` uses SNMPv2c. `snmp_v3` uses `authPriv` with SHA-256 authentication and AES privacy. Change protocol choices in `generator.yml` and regenerate `snmp.yml` only after confirming device support.

## Secret

The Deployment expects Secret `snmp-exporter-auth` in namespace `observability` with these keys:

- `v2-community`: SNMPv2c community only
- `v3-username`: SNMPv3 security name only
- `v3-auth-password`: SNMPv3 authentication password only
- `v3-priv-password`: SNMPv3 privacy password only

Each value must have its own dedicated Bitwarden Secrets Manager item. Do not store a whole `auths` block in any item. Create the Secret without printing values, enabling shell tracing, or writing a rendered Secret to disk:

```sh
set +x
export SNMP_V2_COMMUNITY="$(bws secret get <v2-item-id> -o json | jq -r .value)"
export SNMP_V3_USERNAME="$(bws secret get <v3-user-item-id> -o json | jq -r .value)"
export SNMP_V3_AUTH_PASSWORD="$(bws secret get <v3-auth-item-id> -o json | jq -r .value)"
export SNMP_V3_PRIV_PASSWORD="$(bws secret get <v3-priv-item-id> -o json | jq -r .value)"

kubectl -n observability create secret generic snmp-exporter-auth \
  --from-literal=v2-community="${SNMP_V2_COMMUNITY}" \
  --from-literal=v3-username="${SNMP_V3_USERNAME}" \
  --from-literal=v3-auth-password="${SNMP_V3_AUTH_PASSWORD}" \
  --from-literal=v3-priv-password="${SNMP_V3_PRIV_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

unset SNMP_V2_COMMUNITY SNMP_V3_USERNAME SNMP_V3_AUTH_PASSWORD SNMP_V3_PRIV_PASSWORD
```

Replace each placeholder ID only after creating the named Bitwarden item. The Secret is deliberately absent from Git.

## Target Gate

Before wiring this component into Flux, commit one `VMStaticScrape` endpoint per confirmed device. Each endpoint must state the stable device name, management address, exporter module, auth profile, polling interval, and `always-on` or `intermittent` availability class. Do not infer missing addresses or scan a subnet.

Perform narrow discovery of `sysName.0`, `sysDescr.0`, and `sysObjectID.0` from the confirmed seed list before finalizing modules. Use a 60-second interval for ordinary network devices, 30 seconds for APC UPS devices, and suppress offline alerts for the intermittent Brother printer.

## Validation

Render the component and validate it against the live API:

```sh
kubectl kustomize kubernetes/flux/observability/snmp
kubectl kustomize kubernetes/flux/observability/snmp | kubectl apply --server-side --dry-run=server -f -
```

Use server-side apply for validation because the selected generated modules exceed Kubernetes' client-side last-applied annotation limit. The ConfigMap itself remains below the Kubernetes object-size limit, and Flux also reconciles it with server-side apply.

After credentials and targets are present, require a Ready exporter with no repeated restarts, an `up=1` self-scrape, successful SNMPv2c and SNMPv3 discovery, stable target labels, bounded series counts, and no credentials in pod arguments, rendered manifests, logs, or metrics.

Routine rollback removes or suspends the future Flux Kustomization. The external Secret may remain for redeployment, but delete it explicitly if SNMP monitoring is abandoned.
