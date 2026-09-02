# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, Kubernetes BGP peering, and the declarative IPv4 firewall policy for the homelab gateway.

## Firewall baseline adoption

The first firewall stage adopts verified existing rules without adding a new default-deny policy or reordering the live chains. This keeps the change reviewable and avoids changing behavior before the existing RouterOS policy is represented in OpenTofu state.

The live baseline recorded two active WireGuard interfaces: `wg-roadwarrior` on UDP/51820 with tunnel network `10.1.250.0/24`, and `wireguard1` on UDP/51280 with site-to-site routes for `10.2.0.0/16`. The current peer resources remain outside this issue and are tracked by #302.

The adopted input exceptions are `wireguard` on `wg-roadwarrior`, `SSH LAN IN` on TCP/22, `LAN k3s` from `10.42.0.0/16` to UDP/161, `SNMP LAN IN` on UDP/161 from `LAN`, and `Allow WireGuard roadwarrior` on UDP/51820. The adopted forward exceptions are the existing `10.1.0.0/16` to `10.2.0.0/16` site-to-site path and the `KNOWN WAN` path sourced from the existing `ACCD` address list. The four Kubernetes SNMP exceptions remain separately managed at their existing Terraform resource addresses.

The inventory also confirmed the existing RouterOS default input and forward rules, IPsec rules, fasttrack rule, WAN DST-NAT behavior, and interface-list membership. Those rules remain deliberately unmanaged in this adoption stage; the later default-deny design must be based on their verified behavior rather than replacing them implicitly.

The focused WireGuard contract now owns the two verified listener ports and the peer forwarding boundaries needed by #302: UDP/51820 for `wg-roadwarrior`, UDP/51280 for `wireguard1`, `10.1.250.0/24` from `wg-roadwarrior` to the trusted `LAN` interface list, and `10.2.0.0/16` from `wireguard1` to the trusted `LAN` interface list. This does not create or modify peer keys; peer ownership remains the separate #302 change. The broader default-deny policy remains deferred.

The peer adoption map covers `SH`, disabled `CK`, `Viktor MacBookPro`, and `ipad` with their verified public keys, allowed addresses, endpoints, and comments. Interface private keys and the existing `SH` preshared key are retained in sensitive provider state through lifecycle ignores; no key values are committed or printed. The temporary import blocks were removed after the dedicated `apply_gateway_wireguard=true` adoption, and the next targeted plan must remain clean.

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
