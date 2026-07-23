# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, and Kubernetes BGP peering for the homelab gateway.

## SNMP

The stack owns the gateway's two read-only monitoring identities. SNMPv2c remains available for compatibility, and SNMPv3 uses SHA1 authentication with AES privacy because that is the strongest authPriv combination supported by RouterOS. Both identities accept requests only from the deliberately broad homelab boundary `10.0.0.0/8`; neither has write access.

Bitwarden Secrets Manager items contain one value each:

- `SK-TALOS-SNMP-V2-COMMUNITY` (`f59a5c29-2dc7-4acf-b74b-b48e015b7439`): community only
- `SK-TALOS-SNMP-V3-USERNAME` (`1ae61563-170c-4a94-9fdf-b48e015b7484`): security name only
- `SK-TALOS-SNMP-V3-AUTH-PASSWORD` (`12e0ba06-701b-400d-821d-b48e015b74cd`): authentication password only
- `SK-TALOS-SNMP-V3-PRIV-PASSWORD` (`90e81979-e50d-46e9-9177-b48e015b751a`): privacy password only

The first declarative application imports the remediated live communities by RouterOS IDs `*0` and `*2`. Until the pinned provider's RouterOS 7.21/7.22 IP-address and BGP defects are fixed, dispatch the OpenTofu workflow from `main` with `apply_gateway_snmp=true`. That path creates and applies an immutable plan targeted only at the two SNMP resources. Do not combine it with `apply_gateway=true`.

## Kubernetes BGP

The gateway peers with the Talos Kubernetes nodes on VLAN 20:

- Gateway address: `10.1.20.1`
- Node peers: `10.1.20.41`, `10.1.20.42`, `10.1.20.43`, `10.1.20.44`
- ASN: `65001` on both sides
- Accepted routes: `/32` LoadBalancer VIP routes inside `10.1.30.0/24`

The BGP sessions use TCP MD5 authentication. Export the shared key from Bitwarden before running `tofu plan` or `tofu apply`:

```bash
export TF_VAR_kubernetes_bgp_tcp_md5_key="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
```

Keep shell tracing disabled while this variable is set. Do not commit the plaintext key, local variable files, or generated OpenTofu plans.
