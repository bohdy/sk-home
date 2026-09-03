# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, Kubernetes BGP peering, and the declarative IPv4 firewall policy for the homelab gateway.

## Declarative firewall policy

The live baseline was captured by the trusted, read-only inventory run [33643703527](https://github.com/bohdy/sk-home/actions/runs/33643703527) on 2026-09-02. It contained 28 filter rules, two address-list entries, six interface lists, two active WireGuard interfaces, four WireGuard peers, 28 RouterOS services, and three NAT rules. The baseline confirmed `LAN` membership for VLANs 10, 20, and 100 plus the managed physical ports, `WAN` membership for `ether8`, the two WireGuard listeners, the existing IPsec rules, fasttrack, Kubernetes service VIP list, and the active TCP/32400 WAN destination NAT.

The policy keeps the current OpenTofu resource addresses for the adopted rules. Unsafe broad input exceptions are disabled in place, while the verified site-to-site, known-WAN, and WireGuard forwarding exceptions remain active and are ordered with the new policy. Existing unmanaged RouterOS rules are retained after the managed sequence as a deliberate rollback boundary; they are not used to provide an allow path after the explicit default-deny rules.

The input chain is ordered by `routeros_move_items.input_rules` as follows:

| Order | Rule | Policy |
| ---: | --- | --- |
| 1 | `sk-firewall/input/accept-established-related` | Accept established, related, and untracked sessions. |
| 2 | `sk-firewall/input/drop-invalid` | Drop invalid connection-tracking state. |
| 3 | `sk-firewall/input/allow-icmp-trusted` | Allow ICMP from the trusted `LAN` interface list. |
| 4 | `sk-firewall/input/allow-loopback` | Preserve local loopback traffic used by CAPsMAN. |
| 5 | `sk-firewall/input/allow-dhcp` | Allow trusted VLAN DHCP client traffic from UDP/68 to UDP/67. |
| 6-7 | `sk-firewall/input/allow-dns-udp`, `sk-firewall/input/allow-dns-tcp` | Allow trusted VLAN clients to use the gateway resolver on port 53. |
| 8-9 | `sk-firewall/input/allow-ipsec-esp`, `sk-firewall/input/allow-ipsec-handshake` | Preserve IPsec ESP and UDP/500,4500 negotiation. |
| 10 | `sk-firewall/input/allow-kubernetes-bgp` | Allow TCP/179 only from the six declared Kubernetes node addresses on VLAN 20. |
| 11 | `sk-firewall/input/allow-snmp-monitoring` | Allow UDP/161 only from the existing `10.0.0.0/8` monitoring boundary. |
| 12 | `sk-firewall/input/allow-management` | Allow TCP/22 and TCP/443 only from `10.1.100.0/24`. |
| 13-14 | Verified WireGuard handshakes | Allow UDP/51820 and UDP/51280 only from the `WAN` interface list. |
| 15 | `sk-firewall/input/drop-unmatched` | Drop every remaining input packet. |

The forward chain is ordered by `routeros_move_items.forward_rules` as follows:

| Order | Rule | Policy |
| ---: | --- | --- |
| 1 | `sk-firewall/forward/fasttrack-established-related` | Preserve the verified fasttrack behavior for established and related flows. |
| 2 | `sk-firewall/forward/accept-established-related` | Accept established, related, and untracked sessions. |
| 3 | `sk-firewall/forward/drop-invalid` | Drop invalid connection-tracking state. |
| 4-5 | `sk-firewall/forward/allow-ipsec-in`, `sk-firewall/forward/allow-ipsec-out` | Preserve IPsec policy traffic. |
| 6 | `sk-firewall/forward/allow-trusted-lan-to-wan` | Allow trusted LAN egress to the WAN interface list. |
| 7-10 | Verified baseline forward rules | Preserve site-to-site `10.1.0.0/16` to `10.2.0.0/16`, `KNOWN WAN` from `ACCD`, and the two exact WireGuard-to-LAN paths. |
| 11 | `sk-firewall/forward/allow-kubernetes-service-vips` | Allow trusted LAN access to the Kubernetes service VIP address list. |
| 12-15 | Existing Kubernetes SNMP rules | Preserve the narrow Synology and UniFi request/reply pairs. |
| 16 | `forward_management` | Empty by default; new inter-VLAN management requires a commented map entry. |
| 17 | `sk-firewall/forward/allow-wan-dstnat` | Preserve only new WAN flows that matched the active destination NAT rule. |
| 18 | `sk-firewall/forward/drop-inter-vlan` | Drop unauthorized trusted-LAN to trusted-LAN forwarding. |
| 19 | `sk-firewall/forward/drop-wan-inbound` | Drop new WAN-to-LAN flows that are not destination-NATed. |
| 20 | `sk-firewall/forward/drop-unmatched` | Drop every remaining forwarded packet. |

The WireGuard forwarding policy uses the verified active road-warrior addresses `10.1.250.10/32` and `10.1.250.11/32`, and the verified site peer route `10.2.0.0/16`. Adding a peer or management path requires a non-secret variable change and a new reviewed policy plan; no private key or preshared key is part of this policy.

Capture or refresh the live baseline from `main` with the read-only workflow:

```bash
gh workflow run routeros-firewall-inventory.yaml --ref main
```

The workflow uploads only projected rule, address, interface, route, service, NAT, and WireGuard metadata. It never writes RouterOS state and never includes private keys, preshared keys, passwords, or raw API responses. Review the artifact against the `firewall_policy` values before applying.

Run the mutually exclusive review-only plan first:

```bash
gh workflow run terraform.yaml --ref main \
  -f apply_gateway=false \
  -f apply_gateway_snmp=false \
  -f plan_gateway_snmp=false \
  -f apply_gateway_firewall=false \
  -f plan_gateway_firewall=true \
  -f apply_gateway_dhcp=false \
  -f apply_gateway_ipfix=false \
  -f apply_cloudflare=false
```

The firewall plan targets only the address-list, filter, and ordering resources in this stack, refuses to upload any artifact containing a delete or replacement, and performs no mutation during review. After reviewing the artifact, run the separate production-gated apply dispatch with `apply_gateway_firewall=true` and `plan_gateway_firewall=false`. Re-run the review-only plan afterward and require an empty change set. Do not repair the live firewall through an imperative REST workaround.

### Rollback

If the review plan is wrong, do not apply its artifact. If a live acceptance probe fails after apply, use RouterOS Safe Mode through the VLAN 100 management path or local console and disable only the affected new terminal drop rule identified by its stable `sk-firewall/...` comment. This is a break-glass recovery action, not the normal ownership path: do not use REST, do not change unrelated rules, and record the temporary change. Correct the non-secret `firewall_policy` declaration, run a new reviewed targeted plan, and re-enable the terminal rule through the production-gated apply. A full declaration revert must be a separately reviewed change; the normal no-destroy guard intentionally refuses rollback artifacts that delete managed resources.

Representative acceptance tests must be run from their actual source networks after the policy apply: resolve and reach the gateway DNS service from VLANs 10, 20, and 100; reach TCP/22 and TCP/443 from a VLAN 100 management host; establish both WireGuard listeners from their WAN peers; reach the Kubernetes VIP and both SNMP request/reply paths from the worker VLAN; verify trusted LAN egress and the existing WAN destination-NAT service; and confirm that an unapproved VLAN-to-VLAN connection, a WAN connection without destination NAT, an unknown TCP/179 source, and an unknown WireGuard source are denied. Record only pass/fail, source class, destination class, and the final managed rule order; never record credentials or raw API responses.

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

The gateway peer inventory must include all six Talos nodes. Use the dedicated, mutually exclusive workflow path when a worker peer or its learned VIP route is missing; it targets only the BGP address list, route filter, and peer resources and refuses plans containing deletes or replacements:

```bash
gh workflow run terraform.yaml --ref main -f plan_gateway_bgp=true
gh workflow run terraform.yaml --ref main -f apply_gateway_bgp=true
```

Review the uploaded `network-gw-bgp-tofuplan` artifact between the two commands. The SMTP VIP `10.1.30.58/32` is advertised only by the worker hosting the relay when its Service uses `externalTrafficPolicy: Local`, so that worker's RouterOS BGP session must be established before the printer can connect.

RouterOS 7.23 renamed the BGP add-path property exposed by its REST API, while the pinned `terraform-routeros` 1.99.1 provider still sends the obsolete top-level `add-path-out` field. The provider therefore cannot create or update these rows on this gateway. The production-gated apply path performs a narrow, idempotent REST recovery using RouterOS's native `afi` and required `instance` fields, omits the incompatible add-path field, imports every recovered row into OpenTofu state, and ignores only the provider's resulting add-path and default-port drift so it cannot issue another incompatible update. It then creates and applies a fresh targeted plan. This is temporary migration scaffolding for the provider incompatibility; do not use an ad-hoc REST request outside that workflow.

## Synology SNMP

The gateway permits only UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to Synology at `10.1.100.10`, plus return packets from Synology source port UDP/161 back to that worker VLAN. The reply exception is inserted before the request exception, so both remain ahead of broader inter-VLAN filtering; neither rule exposes DSM management ports or SNMP to other VLANs.

## UniFi SNMP

The gateway permits UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to the UniFi AP management VLAN `10.1.102.0/24`, plus replies sourced from UDP/161 back to workers. The subnet-level target is intentional: AP addresses are dynamic until the controller migration and DHCP reservations are complete, while the protocol and source VLAN remain constrained.

The BGP sessions use TCP MD5 authentication. The trusted workflow injects the key from Bitwarden without exposing it in logs. For local diagnostics, invoke `bws` only inside the repository devcontainer and keep its output process-local:

```bash
devcontainer exec --workspace-folder /path/to/sk-home sh -ec '
  set +x
  bgp_key="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
  # Use "$bgp_key" only in a command running inside this devcontainer.
  unset bgp_key
'
```

Keep shell tracing disabled while the value is set. Do not commit the plaintext key, local variable files, or generated OpenTofu plans.
