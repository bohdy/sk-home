# MikroTik Gateway DHCP

This stack owns the MikroTik gateway DHCP pools, servers, networks, UniFi option 43, and the pre-existing static reservations retained from the archived DHCP state.

## LAN DNS

Every routed DHCP scope advertises Blocky at `10.1.30.53` as its sole resolver. Blocky is the cluster's LAN-facing DNS VIP and serves the internal `bohdal.name` split-DNS zone before forwarding public recursion through CoreDNS to DNS4EU.

VLAN20 is served by `server20` on `vlan20`, with pool `pool-vlan20` allocating `10.1.20.10` through `10.1.20.250` except the Talos API virtual IP at `.40`. The `gha_runner_vm_01` reservation retains `vm-gha-01` at `10.1.20.200` after it moves from static netplan addressing to DHCP. The Talos control planes and workers are also reserved at `.41` through `.46`, using the MAC and address inventory from the Talos stack; their current noCloud network data remains static until a separately reviewed migration. Every VLAN20 lease receives the internal DNS VIP and therefore resolves `gw.bohdal.name` to the RouterOS management address instead of the public Cloudflare proxy.

Before applying, inspect the immutable plan against the requested change. A new scope should create only its pool, server, and network record (plus explicitly requested reservations); it must not replace unrelated DHCP resources or options.

## State Migration

The backend intentionally retains `sk-home/home/network-core/dhcp/terraform.tfstate`, the archived DHCP key. The migration moves the existing state addresses with the OpenTofu CLI before this stack is planned, then leaves no migration blocks in committed configuration.

The Brother printer and APC UPS are normal static lease resources. A lease must already be static before it is introduced here; this stack never converts dynamic leases imperatively.

## Secrets and Apply

`MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` are one-value Bitwarden Secrets Manager items injected as `TF_VAR_mikrotik_username` and `TF_VAR_mikrotik_password`. The gateway apply path remains manual and production-gated because DHCP changes affect all LAN clients.
