# MikroTik Gateway DHCP

This stack owns the MikroTik gateway DHCP pools, servers, networks, UniFi option 43, and the pre-existing static reservations retained from the archived DHCP state.

## LAN DNS

Every routed DHCP scope advertises Blocky at `10.1.30.53` as its sole resolver. Blocky is the cluster's LAN-facing DNS VIP and serves the internal `bohdal.name` split-DNS zone before forwarding public recursion through CoreDNS to DNS4EU.

The first migration plan must show only DNS-server changes for the four DHCP network records. It must not create or replace a DHCP pool, server, lease, or DHCP option.

## State Migration

The backend intentionally retains `sk-home/home/network-core/dhcp/terraform.tfstate`, the archived DHCP key. The migration moves the existing state addresses with the OpenTofu CLI before this stack is planned, then leaves no migration blocks in committed configuration.

The Brother printer and APC UPS are normal static lease resources. A lease must already be static before it is introduced here; this stack never converts dynamic leases imperatively.

## Secrets and Apply

`MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` are one-value Bitwarden Secrets Manager items injected as `TF_VAR_mikrotik_username` and `TF_VAR_mikrotik_password`. The gateway apply path remains manual and production-gated because DHCP changes affect all LAN clients.
