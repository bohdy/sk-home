# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, and Kubernetes BGP peering for the homelab gateway.

## SNMP

The stack owns the gateway's two read-only monitoring identities. SNMPv2c remains available for compatibility, and SNMPv3 uses SHA1 authentication with AES privacy because that is the strongest authPriv combination supported by RouterOS. Both identities accept requests only from the deliberately broad homelab boundary `10.0.0.0/8`; neither has write access.

Bitwarden Secrets Manager items contain one value each:

- `SK-TALOS-SNMP-V2-COMMUNITY` (`f59a5c29-2dc7-4acf-b74b-b48e015b7439`): community only
- `SK-TALOS-SNMP-V3-USERNAME` (`1ae61563-170c-4a94-9fdf-b48e015b7484`): security name only
- `SK-TALOS-SNMP-V3-AUTH-PASSWORD` (`12e0ba06-701b-400d-821d-b48e015b74cd`): authentication password only
- `SK-TALOS-SNMP-V3-PRIV-PASSWORD` (`90e81979-e50d-46e9-9177-b48e015b751a`): privacy password only

The two gateway SNMP identities are already represented in remote OpenTofu state; no migration blocks remain in the desired-state configuration. Until the pinned provider's RouterOS 7.21/7.22 IP-address and BGP defects are fixed, dispatch the OpenTofu workflow from `main` with `plan_gateway_snmp=true` to produce an immutable plan targeted only at the two SNMP identities and the Synology SNMP forwarding rule. Review it before dispatching the separate `apply_gateway_snmp=true` production-gated apply. Do not combine either input with another gateway or Cloudflare control.

## Kubernetes BGP

The gateway peers with the Talos Kubernetes nodes on VLAN 20:

- Gateway address: `10.1.20.1`
- Node peers: `10.1.20.41`, `10.1.20.42`, `10.1.20.43`, `10.1.20.44`
- ASN: `65001` on both sides
- Accepted routes: `/32` LoadBalancer VIP routes inside `10.1.30.0/24`

## Synology SNMP

The gateway permits only UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to Synology at `10.1.100.10`. The stack reads the current first `forward` rule and inserts the exception before its RouterOS ID, because the provider does not accept a numeric rule position. This keeps the NAS polling path ahead of broader inter-VLAN filtering without exposing DSM management ports or SNMP to other VLANs.

The BGP sessions use TCP MD5 authentication. Export the shared key from Bitwarden before running `tofu plan` or `tofu apply`:

```bash
export TF_VAR_kubernetes_bgp_tcp_md5_key="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
```

Keep shell tracing disabled while this variable is set. Do not commit the plaintext key, local variable files, or generated OpenTofu plans.
