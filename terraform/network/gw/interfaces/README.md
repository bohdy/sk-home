# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, Kubernetes BGP peering, and the declarative IPv4 firewall policy for the homelab gateway.

## Firewall policy

The firewall policy is intentionally fail-closed for router input and unauthorized forwarding. Trusted LAN egress to the WAN is allowed, established and related return traffic is preserved, and unsolicited WAN-to-LAN traffic is denied. The current trusted interface list is `LAN`, which contains VLANs 10, 20, and 100 in `vlans.auto.tfvars`; VLANs 101 and 102 remain outside that broad trust boundary.

The input chain is ordered as follows:

| Order | Rule | Policy |
| ---: | --- | --- |
| 1 | `sk-firewall/input/accept-established-related` | Accept established and related connections. |
| 2 | `sk-firewall/input/drop-invalid` | Drop invalid connection-tracking state. |
| 3 | `sk-firewall/input/allow-icmp-trusted` | Allow ICMP from the trusted interface list. |
| 4 | `sk-firewall/input/allow-dhcp` | Allow DHCP client UDP/68 to UDP/67 from trusted VLANs. |
| 5 | `sk-firewall/input/allow-kubernetes-bgp` | Allow TCP/179 from the six declared Kubernetes node addresses on VLAN 20. |
| 6 | `sk-firewall/input/allow-snmp-monitoring` | Allow UDP/161 from the existing `10.0.0.0/8` SNMP boundary. |
| 7 | `sk-firewall/input/allow-management` | Allow TCP/443 from the VLAN 100 management source list. Additional ports require a reviewed policy entry. |
| 8 | `sk-firewall/input/allow-wireguard` | Allow the verified WireGuard UDP listen port on the WAN interface. Disabled until live WireGuard inventory supplies the interface, tunnel CIDR, and port. |
| 9 | `sk-firewall/input/drop-unmatched` | Drop all remaining input traffic. |

The forward chain permits trusted LAN to WAN traffic, preserves established and related sessions, permits trusted LAN access to the Kubernetes service VIP address list, and then denies unauthorized inter-VLAN and inbound WAN paths. The existing SNMP exceptions remain narrow and precede the inter-VLAN drop:

| Rule | Source | Destination | Service |
| --- | --- | --- | --- |
| `allow_kubernetes_synology_snmp` | `10.1.20.0/24` | `10.1.100.10` | UDP/161 |
| `allow_synology_snmp_responses` | `10.1.100.10` | `10.1.20.0/24` | UDP source port 161 |
| `allow_kubernetes_unifi_snmp` | `10.1.20.0/24` | `10.1.102.0/24` | UDP/161 |
| `allow_unifi_snmp_responses` | `10.1.102.0/24` | `10.1.20.0/24` | UDP source port 161 |

The remaining forward rules are `sk-firewall/forward/accept-established-related`, `sk-firewall/forward/drop-invalid`, `sk-firewall/forward/allow-trusted-lan-to-wan`, `sk-firewall/forward/allow-wireguard-to-trusted-lan`, `sk-firewall/forward/allow-kubernetes-service-vips`, `sk-firewall/forward/drop-inter-vlan`, `sk-firewall/forward/drop-wan-inbound`, and `sk-firewall/forward/drop-unmatched`. WireGuard peers are allowed to reach all trusted LAN interfaces once the verified tunnel values enable that rule; they are not allowed to bypass the untrusted VLAN boundary.

Before enabling or applying the policy, capture the live baseline from `main` with the read-only workflow:

```bash
gh workflow run routeros-firewall-inventory.yaml --ref main
```

The workflow uploads only projected rule, address, interface, route, service, NAT, and WireGuard metadata. It never writes RouterOS state and never includes private keys, preshared keys, passwords, or raw API responses. Use the resulting artifact to confirm existing rules, address-list ownership, interface-list membership, management ports, WireGuard values, and the ordering anchors before changing `firewall_policy`.

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

The plan job refuses to upload any artifact containing a delete or replacement. The apply job consumes only that immutable artifact in the `production` environment. If the policy blocks an intended path, revert the policy commit and run the reviewed targeted plan again; do not repair the live firewall through an imperative REST workaround.

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
