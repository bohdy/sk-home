# DNS infrastructure

This component deploys the LAN DNS path for the `sk-talos` cluster. Blocky is the only LAN-facing resolver at `10.1.30.53`; CoreDNS stays internal and serves the split `bohdal.name` view plus DNS4EU forwarding.

The detailed design record is [docs/dns-design.md](../../../../docs/dns-design.md). Operational notes that should inform future work, including observability stack inputs, are kept in [docs/project-memory.md](../../../../docs/project-memory.md).

## Layout

- `src/` is the human-edited source of truth.
- `src/coredns/zones/` contains RFC-style zone files.
- `rendered/` is generated output applied by Flux.
- `scripts/render-dns.py` updates changed SOA serials, generates CoreDNS ConfigMaps, and injects rollout checksum annotations.

Do not edit files under `rendered/` directly. Edit `src/`, then regenerate.

## Render and validate

From the repository root:

```bash
mise run dns-render
mise run dns-check
```

`dns-render` updates generated files. `dns-check` verifies generated output and runs `kubectl kustomize kubernetes/flux/infrastructure/dns/rendered`.

## Updating records

Edit the relevant zone file under `src/coredns/zones/`, then run `mise run dns-render`. The renderer updates SOA serials only for zone files with substantive DNS data changes. Serial format is `YYYYMMDDNN`.

Initial internal records:

- `dns.bohdal.name` -> `10.1.30.53`
- `blocky.bohdal.name` -> `10.1.30.53`
- `grafana.bohdal.name` -> `10.1.30.55`
- `grafana.internal.bohdal.name` -> `10.1.30.55`
- `gw.bohdal.name` -> `10.1.100.1`
- `printer.sk.bohdal.name` -> `10.1.10.13`

Reverse records are expected for committed infrastructure records.

## Smoke tests

Before changing DHCP, test directly from LAN clients on each relevant VLAN:

```bash
dig @10.1.30.53 dns.bohdal.name A
dig @10.1.30.53 blocky.bohdal.name A
dig @10.1.30.53 grafana.bohdal.name A
dig @10.1.30.53 grafana.internal.bohdal.name A
dig @10.1.30.53 gw.bohdal.name A
dig @10.1.30.53 printer.sk.bohdal.name A
dig @10.1.30.53 -x 10.1.30.53
dig @10.1.30.53 -x 10.1.30.55
dig @10.1.30.53 -x 10.1.100.1
dig @10.1.30.53 www.bohdal.name A
dig @10.1.30.53 example.com A
dig +tcp @10.1.30.53 dns.bohdal.name A
dig +tcp @10.1.30.53 example.com A
```

Public-name tests should assert successful resolution, not exact public IP addresses.

## Rollback

Before MikroTik DHCP points clients at `10.1.30.53`, rollback is disabling or removing the DNS Flux Kustomization and rendered manifests. After DHCP changes, rollback must also restore the previous DHCP DNS option.
