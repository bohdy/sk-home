# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, Kubernetes BGP peering, and the declarative IPv4 firewall policy for the homelab gateway.

## Firewall baseline adoption

The first firewall stage adopts verified existing rules without adding a new default-deny policy or reordering the live chains. This keeps the change reviewable and avoids changing behavior before the existing RouterOS policy is represented in OpenTofu state.

The live baseline recorded two active WireGuard interfaces: `wg-roadwarrior` on UDP/51820 with tunnel network `10.1.250.0/24`, and `wireguard1` on UDP/51280 with site-to-site routes for `10.2.0.0/16`. The current peer resources remain outside this issue and are tracked by #302.

The adopted input exceptions are `wireguard` on `wg-roadwarrior`, `SSH LAN IN` on TCP/22, `LAN k3s` from `10.42.0.0/16` to UDP/161, `SNMP LAN IN` on UDP/161 from `LAN`, and `Allow WireGuard roadwarrior` on UDP/51820. The adopted forward exceptions are the existing `10.1.0.0/16` to `10.2.0.0/16` site-to-site path and the `KNOWN WAN` path sourced from the existing `ACCD` address list. The four Kubernetes SNMP exceptions remain separately managed at their existing Terraform resource addresses.

The inventory also confirmed the existing RouterOS default input and forward rules, IPsec rules, fasttrack rule, WAN DST-NAT behavior, and interface-list membership. Those rules remain deliberately unmanaged in this adoption stage; the later default-deny design must be based on their verified behavior rather than replacing them implicitly.

The focused WireGuard contract now owns the two verified listener ports and the peer forwarding boundaries needed by #302: UDP/51820 for `wg-roadwarrior`, UDP/51280 for `wireguard1`, `10.1.250.0/24` from `wg-roadwarrior` to the trusted `LAN` interface list, and `10.2.0.0/16` from `wireguard1` to the trusted `LAN` interface list. This does not create or modify peer keys; peer ownership remains the separate #302 change. The broader default-deny policy remains deferred.

Capture the live baseline from `main` with the read-only workflow:

```bash
gh workflow run routeros-firewall-inventory.yaml --ref main
```

The workflow uploads only projected rule, address, interface, route, service, NAT, and WireGuard metadata. It never writes RouterOS state and never includes private keys, preshared keys, passwords, or raw API responses. The resulting artifact is the source for the adoption maps in `firewall_policy`.

The targeted firewall plan and apply path is mutually exclusive with every other gateway mutation mode:

```bash
gh workflow run terraform.yaml --ref main \
  -f apply_gateway=false \
  -f apply_gateway_snmp=false \
  -f plan_gateway_snmp=false \
  -f apply_gateway_firewall=true \
  -f apply_gateway_dhcp=false \
  -f apply_gateway_ipfix=false \
  -f apply_cloudflare=false
```

The targeted plan imported only the verified baseline exceptions and refused to upload any artifact containing a delete or replacement. The temporary import blocks were removed immediately after that production-gated adoption; the next targeted plan must remain clean. Do not repair the live firewall through an imperative REST workaround.

## IPFIX flow collection

The `ipfix.tf` traffic-flow resource exports routed WAN and VLAN traffic to the goflow2 NodePort. Its interface list is derived from `vlans.auto.tfvars` and includes `ether8` plus every VLAN with a managed gateway address; the bridge is intentionally excluded so same-VLAN switching is outside the collector scope and overlapping selectors do not duplicate records. Review the targeted plan and verify live flow counts before applying changes through the mutually exclusive `apply_gateway_ipfix=true` workflow path.

## SNMP

The stack owns the gateway's two read-only monitoring identities. SNMPv2c remains available for compatibility, and SNMPv3 uses SHA1 authentication with AES privacy because that is the strongest authPriv combination supported by RouterOS. Both identities accept requests only from the deliberately broad homelab boundary `10.0.0.0/8`; neither has write access.

Bitwarden Secrets Manager items contain one value each:

- `SK-TALOS-SNMP-V2-COMMUNITY` (`f59a5c29-2dc7-4acf-b74b-b48e015b7439`): community only
- `SK-TALOS-SNMP-V3-USERNAME` (`1ae61563-170c-4a94-9fdf-b48e015b7484`): security name only
- `SK-TALOS-SNMP-V3-AUTH-PASSWORD` (`12e0ba06-701b-400d-821d-b48e015b74cd`): authentication password only
- `SK-TALOS-SNMP-V3-PRIV-PASSWORD` (`90e81979-e50d-46e9-9177-b48e015b751a`): privacy password only

The two gateway SNMP identities are already represented in remote OpenTofu state; no migration blocks remain in the desired-state configuration. Until the pinned provider's RouterOS 7.21/7.22 IP-address and BGP defects are fixed, dispatch the OpenTofu workflow from `main` with `plan_gateway_snmp=true` to produce an immutable plan targeted only at the two SNMP identities and the Synology and UniFi SNMP forwarding rules. Review it before dispatching the separate `apply_gateway_snmp=true` production-gated apply. Do not combine either input with another gateway or Cloudflare control.

## Kubernetes BGP

The gateway peers with the Talos Kubernetes nodes on VLAN 20:

- Gateway address: `10.1.20.1`
- Node peers: `10.1.20.41`, `10.1.20.42`, `10.1.20.43`, `10.1.20.44`, `10.1.20.45`, `10.1.20.46`
- ASN: `65001` on both sides
- Accepted routes: `/32` LoadBalancer VIP routes inside `10.1.30.0/24`

## Synology SNMP

The gateway permits only UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to Synology at `10.1.100.10`, plus return packets from Synology source port UDP/161 back to that worker VLAN. The reply exception is inserted before the request exception, so both remain ahead of broader inter-VLAN filtering; neither rule exposes DSM management ports or SNMP to other VLANs.

## UniFi SNMP

The gateway permits UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to the UniFi AP management VLAN `10.1.102.0/24`, plus replies sourced from UDP/161 back to workers. The subnet-level target is intentional: AP addresses are dynamic until the controller migration and DHCP reservations are complete, while the protocol and source VLAN remain constrained.

The BGP sessions use TCP MD5 authentication. Export the shared key from Bitwarden before running `tofu plan` or `tofu apply`:

```bash
export TF_VAR_kubernetes_bgp_tcp_md5_key="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
```

Keep shell tracing disabled while this variable is set. Do not commit the plaintext key, local variable files, or generated OpenTofu plans.
