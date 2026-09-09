# MikroTik gateway interfaces

This stack manages the MikroTik gateway bridge, VLAN interfaces, interface lists, Kubernetes BGP peering, and the declarative IPv4/IPv6 firewall policy for the homelab gateway.

The Dell Server at `10.1.100.202` on `ether7` carries untagged VLAN 100 traffic and tagged VLAN 20 traffic.

## Optional Proxmox qdevice

The optional `qdevice` object runs the pinned `lpgonzalez/corosync-qnetd:1.0.0` image on the RouterOS container package. It is disabled by default, so existing plans remain unchanged. When enabled, OpenTofu creates `veth-qnetd` at `10.1.100.252/24` with gateway `10.1.100.1`, places it untagged in VLAN 100, records the desired USB-backed container mounts and native `mountlists`, and writes the supplied Proxmox SSH public key to the qnetd `authorized_keys` file.

Enable it only after the USB drive is formatted with a RouterOS-supported filesystem and the parent paths `usb1/qnetd`, `usb1/qnetd/root`, `usb1/qnetd/layers`, `usb1/qnetd/tmp`, `usb1/qnetd/nssdb`, `usb1/qnetd/ssh-host-keys`, and `usb1/qnetd/ssh-authorized-keys` exist as directories. The targeted workflow supplies `qdevice.ssh_public_key` from the committed `qdevice-authorized.pub` cluster key; direct stack callers must provide an equivalent public key through the protected variable injection path. It must be non-empty when `qdevice.enabled` is true. This change adds no firewall rules because the qdevice and Proxmox nodes share the existing VLAN 100 Layer-2 segment.

The RouterOS container configuration is global, so the targeted workflow fails closed if any other container exists, if a populated container uses extraction paths different from these USB-backed paths, or if the existing registry is not Docker Hub. When the live container list is empty, the reviewed initial artifact may declaratively migrate the global extraction paths to the qnetd paths; it never adopts arbitrary live paths or deletes old directories. RouterOS exposes the provider-owned global extraction fields with a leading `/` (`/usb1/qnetd/layers` and `/usb1/qnetd/tmp`), while file and native mount paths use `usb1/...`; the workflow canonicalizes only the latter for directory checks. Review this global configuration before enabling qnetd because changing it can affect every RouterOS container. The pinned RouterOS provider currently rejects its `routeros_container_mounts` `name` payload on RouterOS 7.23 and cannot safely own the container's native `mountlists` field. The initial reviewed artifact creates the provider-managed prerequisites and state-only desired records; the production-gated recovery script is the only owner of the two incompatible live objects, uses native `list`/`mountlists` fields, and never deletes them. The authorized key is the Proxmox cluster's public root SSH key, committed as public material and guarded by fingerprint `SHA256:9x+cumin8611j5uKUYwq2kTRI6nVbTtxF9GoeISjeF8`; no private key is needed by the qdevice workflow or placed in OpenTofu state or RouterOS.

Review and apply qdevice changes only from `main` through the mutually exclusive targeted workflow. A plan-only run adopts and validates the existing veth, bridge port, VLAN 100 row, and global container configuration, creates the immutable `network-gw-qdevice-tofuplan` artifact, and rejects deletes, replacements, or unrelated resources. Review that initial artifact before approving the first production gate; if it migrates global extraction paths, the recovery job rechecks that the RouterOS container list is still empty immediately before applying it. Before any production apply, run the repository's fresh read-only firewall inventory and confirm the existing VLAN 100 policy remains the intended boundary. The recovery job then reconciles the native mounts/container, creates `network-gw-qdevice-recovery-tofuplan`, and pauses again before the second job applies only that fresh artifact. Review the recovered artifact before approving the second gate, then run the review-only dispatch again and require an empty plan.

If review shows an unexpected change, or the preflight reports conflicting `layer-dir`, `tmpdir`, or a conflicting/non-qnetd container including a stopped one, inspect the live `/rest/container` and `/rest/container/config` state and do not manually change paths or blindly retry. If post-apply verification fails, do not retry an unreviewed plan; use RouterOS Safe Mode or the local console only to stop qnetd if necessary, preserve the USB data and global container configuration, correct the declaration, and create a new reviewed plan. The targeted no-destroy guard rejects destructive rollback artifacts, so qdevice removal requires a separately reviewed operation.

## Declarative firewall policy

The trusted, read-only inventory run [33994757629](https://github.com/bohdy/sk-home/actions/runs/33994757629) captured the current live baseline from `main` on 2026-09-05. It contained 61 IPv4 filter rules, 11 IPv4 address-list entries, three IPv4 NAT rules, one IPv4 raw rule, three IPv4 mangle rules, zero bridge-filter rules, 26 IPv6 filter rules, one IPv6 NAT rule, one IPv6 mangle rule, and nine IPv6 firewall address-list entries, plus six interface lists, 12 interface-list members, 22 interfaces, 13 IPv4 addresses, 48 routes, two active WireGuard interfaces, four WireGuard peers, and 31 RouterOS services. The baseline recorded `LAN` membership for VLANs 10, 20, and 100 plus the managed physical ports, `WAN` membership for `ether8`, the two WireGuard listeners, the existing IPsec rules, FastTrack, Kubernetes service VIP list, and the active TCP/32400 WAN destination NAT. It also exposed the broad `lan-to-nas` accept before FastTrack; the implementation disables that legacy rule while adding exact routed Synology policy.

The policy keeps the current OpenTofu resource addresses for the adopted rules. Unsafe broad input and legacy NAS/VLAN exceptions are disabled in place, while the verified site-to-site, known-WAN, and WireGuard forwarding exceptions remain active and are ordered with the new policy. All captured RouterOS firewall-table rows are state-owned; redundant imported IPv4 filter rules remain after the canonical terminal drops as a deliberate counter-backed cleanup boundary and cannot provide an allow path. Generated FastTrack counter rows remain state-owned at RouterOS-generated positions and are never moved.

The pre-apply targeted hardening plan had 24 creates, 10 in-place updates, and 0 deletes or replacements. It includes the dedicated `sk-internal-vlans` interface boundary, five internal-network address-list entries, one missing VLAN 10 management entry, four exact routed Synology rules, the Kubernetes-to-Proxmox exporter exception for `10.1.100.201`, the matching Dell Server API exception for `10.1.100.202`, ownership checks, and the IPv6 filter/NAT ordering resources; it also updates DHCP, Kubernetes service-VIP matching, the road-warrior destination boundary, and filter ordering. The isolated exporter exception was applied by [run 34215941200](https://github.com/bohdy/sk-home/actions/runs/34215941200); the broader hardening plan remains unapplied. The complete rule-by-rule review is in [FIREWALL_REVIEW.md](./FIREWALL_REVIEW.md).

The input chain is ordered by `routeros_move_items.input_rules` as follows:

| Order | Rule | Policy |
| ---: | --- | --- |
| 1 | `sk-firewall/input/accept-established-related` | Accept established, related, and untracked sessions. |
| 2 | `sk-firewall/input/drop-invalid` | Drop invalid connection-tracking state. |
| 3 | `sk-firewall/input/allow-loopback` | Preserve local loopback traffic used by CAPsMAN. |
| 4 | `sk-firewall/input/allow-dhcp` | Allow DHCP client traffic from every addressed VLAN through `sk-internal-vlans`, including VLANs 101 and 102. |
| 5-6 | `sk-firewall/input/allow-dns-udp`, `sk-firewall/input/allow-dns-tcp` | Allow trusted `LAN` clients to use the gateway resolver on port 53; VLANs 101 and 102 use the Kubernetes DNS VIP through the forward chain. |
| 7 | `sk-firewall/input/allow-icmp-trusted` | Allow ICMP from the trusted `LAN` interface list. |
| 8-9 | `sk-firewall/input/allow-ipsec-esp`, `sk-firewall/input/allow-ipsec-handshake` | Preserve IPsec ESP and UDP/500,4500 negotiation. |
| 10 | `sk-firewall/input/allow-kubernetes-bgp` | Allow TCP/179 only from the six declared Kubernetes node addresses on VLAN 20. |
| 11 | `sk-firewall/input/allow-snmp-monitoring` | Allow UDP/161 from the existing `10.0.0.0/8` monitoring boundary, which includes the Kubernetes exporter pod source range. |
| 12 | `sk-firewall/input/allow-management` | Allow TCP/22 and TCP/443 only from the explicit VLAN 10 and VLAN 100 management source entries. |
| 13-15 | Active runner and WireGuard handshakes | Allow the verified runner HTTPS path and UDP/51820 and UDP/51280 only from their documented source/interface constraints. |
| 16 | `sk-firewall/input/drop-unmatched` | Drop every remaining input packet. |

The forward chain is ordered by `routeros_move_items.forward_rules` as follows:

| Order | Rule | Policy |
| ---: | --- | --- |
| 1-2 | `sk-firewall/forward/allow-ipsec-in`, `sk-firewall/forward/allow-ipsec-out` | Preserve IPsec policy traffic before FastTrack, as required by RouterOS IPsec bypass handling. |
| 3 | `sk-firewall/forward/fasttrack-established-related` | Preserve the verified FastTrack behavior for established and related flows after IPsec exceptions. |
| 4 | `sk-firewall/forward/accept-established-related` | Accept established, related, and untracked sessions. |
| 5 | `sk-firewall/forward/drop-invalid` | Drop invalid connection-tracking state. |
| 6-9 | `sk-firewall/forward/allow-synology-vlan-10`, `...-20`, `...-101`, `...-102` | Allow all routed protocols from each inventory VLAN to Synology `10.1.100.10` through inventory-derived source, ingress, and `vlan100` egress interfaces. |
| 10 | `sk-firewall/forward/allow-trusted-lan-to-wan` | Allow trusted LAN egress to the WAN interface list; the dedicated internal list is not used for general WAN access. |
| 11-14 | Verified baseline forward rules | Preserve site-to-site `10.1.0.0/16` to `10.2.0.0/16`, `KNOWN WAN` from `ACCD`, and the two WireGuard-to-LAN paths, with the road-warrior rule excluding `10.1.30.0/24`. |
| 15 | `sk-firewall/forward/allow-kubernetes-service-vips` | Allow all addressed VLANs to Kubernetes VIPs only when both `sk-internal-vlan-networks` and `sk-internal-vlans` match, excluding SMTP relay VIP `10.1.30.58`. |
| 16-17 | `sk-firewall/forward/allow-wireguard-kubernetes-dns-udp`, `sk-firewall/forward/allow-wireguard-kubernetes-dns-tcp` | Allow only the verified road-warrior addresses to use the Kubernetes DNS VIP. |
| 18 | `sk-firewall/forward/allow-smtp-relay-from-printer` | Allow only printer `10.1.10.250/32` to submit SMTP over TCP/587 to relay VIP `10.1.30.58`. |
| 19-22 | Existing Kubernetes SNMP rules | Preserve the narrow Synology and UniFi request and reply paths; the imported Synology reply rule remains enabled until post-apply counter testing proves it redundant. |
| 23 | `sk-firewall/forward/allow-kubernetes-proxmox` | Allow the Kubernetes worker VLAN to reach the Proxmox API at `10.1.100.201:8006`; this is the exporter’s only routed management exception. |
| 24 | `sk-firewall/forward/allow-kubernetes-dell` | Allow the Kubernetes worker VLAN to reach the Dell Server’s Proxmox-compatible API at `10.1.100.202:8006`, using the same narrow rule as the original node. |
| 25-26 | `sk-firewall/forward/allow-management-proxmox`, `sk-firewall/forward/allow-management-dell` | Allow VLAN 10 administrators to reach the Proxmox-compatible APIs at `10.1.100.201:8006` and `10.1.100.202:8006` with identical narrow TCP rules. |
| 27 | `forward_management` | Empty by default; new inter-VLAN management requires a commented map entry. |
| 28 | `sk-firewall/forward/allow-wan-dstnat` | Preserve only new WAN flows that matched the active destination NAT rule. |
| 29 | `sk-firewall/forward/drop-inter-vlan` | Drop unauthorized trusted-LAN to trusted-LAN forwarding. |
| 30 | `sk-firewall/forward/drop-wan-inbound` | Drop new WAN-to-LAN flows that are not destination-NATed. |
| 31 | `sk-firewall/forward/drop-unmatched` | Drop every remaining forwarded packet. |
| 32+ | Retired and other imported rollback rules | Remain after the terminal deny and cannot provide an allow path; every captured identity remains state-owned. The generated FastTrack dummy is state-owned separately and is not moved. |

The WireGuard forwarding policy uses the verified active road-warrior addresses `10.1.250.10/32` and `10.1.250.11/32` through a dedicated RouterOS address list, plus the verified site peer route `10.2.0.0/16`. The road-warrior rule retains its existing broad trusted-LAN access except for Kubernetes VIPs; the dedicated DNS exceptions permit UDP/TCP 53 at `10.1.30.53`. The printer exception is limited to TCP/587 from `10.1.10.250/32` to SMTP relay VIP `10.1.30.58`; it does not grant the printer general access to other VLAN services. The Proxmox-compatible API exceptions permit only VLAN 10 and VLAN 20 sources to reach the two declared node addresses on TCP/8006. Adding a peer or management path requires a non-secret variable change and a new reviewed policy plan; no private key or preshared key is part of this policy.

Capture or refresh the live baseline from `main` with the read-only workflow:

```bash
gh workflow run routeros-firewall-inventory.yaml --ref main
```

The workflow uploads only projected IPv4/IPv6 filter, raw, mangle, bridge-filter, NAT, address-list, interface, route, service, and WireGuard metadata. It never writes RouterOS state and never includes private keys, preshared keys, passwords, or raw API responses. Review the artifact against the `firewall_policy` values before applying.

For the firing Proxmox exporter target, use the isolated review-only path so the artifact contains only one new TCP/8006 allow rule:

```bash
gh workflow run terraform.yaml --ref main \
  -f apply_gateway=false \
  -f apply_gateway_snmp=false \
  -f plan_gateway_snmp=false \
  -f apply_gateway_bgp=false \
  -f plan_gateway_bgp=false \
  -f apply_gateway_firewall=false \
  -f plan_gateway_firewall=false \
  -f apply_gateway_proxmox=false \
  -f plan_gateway_proxmox=true \
  -f apply_gateway_wireguard=false \
  -f apply_gateway_dhcp=false \
  -f apply_gateway_ipfix=false \
  -f apply_cloudflare=false
```

Review `network-gw-proxmox-tofuplan` and require exactly one create for `sk-firewall/forward/allow-kubernetes-proxmox`, with no deletes or replacements, before the first apply. The production-gated job applies the immutable artifact and verifies the rule is before `sk-firewall/forward/drop-inter-vlan`; this procedure was used successfully in [run 34215941200](https://github.com/bohdy/sk-home/actions/runs/34215941200). Re-run the review-only dispatch afterward and require an empty plan; the guard accepts that post-apply state. Do not use the broader firewall apply path for this alert.

For the Dell Server on `ether7`, use the dedicated review-only interface path:

```bash
gh workflow run terraform.yaml --ref main -f plan_gateway_ether7=true
```

Review `network-gw-ether7-tofuplan` and require only the Dell Server ether7 comment update, the VLAN 20 tagged and VLAN 100 untagged membership updates, the matching Kubernetes-to-Dell TCP/8006 firewall rule for `10.1.100.202`, and identical VLAN 10 management rules for both Proxmox-compatible nodes, with no deletes or replacements. After review, run a separate dispatch with `-f apply_gateway_ether7=true`; the production-gated job applies the immutable artifact and verifies the live physical comment, bridge PVID, managed VLAN memberships, and all three API rules. Re-run the review-only dispatch afterward and require an empty plan.

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

The firewall plan targets the dedicated interface boundary, all audited IPv4/IPv6 firewall-table resources, address lists, ownership checks, and ordering resources in this stack, refuses to upload any artifact containing a delete or replacement, and performs no mutation during review. After reviewing the artifact, run the separate production-gated apply dispatch with `apply_gateway_firewall=true` and `plan_gateway_firewall=false`. Re-run the review-only plan afterward and require an empty change set. Do not repair the live firewall through an imperative REST workaround.

### Rollback

If the review plan is wrong, do not apply its artifact. If a live acceptance probe fails after apply, use RouterOS Safe Mode through the VLAN 100 management path or local console and disable only the affected new terminal drop rule identified by its stable `sk-firewall/...` comment. This is a break-glass recovery action, not the normal ownership path: do not use REST, do not change unrelated rules, and record the temporary change. Correct the non-secret `firewall_policy` declaration, run a new reviewed targeted plan, and re-enable the terminal rule through the production-gated apply. A full declaration revert must be a separately reviewed change; the normal no-destroy guard intentionally refuses rollback artifacts that delete managed resources.

The pre-change baseline and read-only physical checks do not establish full-speed acceptance. The live check confirmed ether3 is a forwarding, hardware-offloaded bridge port with PVID 100, VLAN 100 current-untagged membership, bridge firewall processing disabled, one complete ARP owner for `10.1.100.10`, and no DHCP lease for that address. Run representative acceptance tests from their actual source networks after the policy apply: reach representative ICMP, TCP, and UDP Synology services from VLANs 10, 20, 101, and 102; verify VLAN 100 Layer-2 access; confirm DHCP and Kubernetes DNS/VIP reachability from every addressed VLAN; confirm the matching Synology allow and established/FastTrack counters increment without terminal-drop counters; run three 60-second, four-stream `iperf3` tests in both directions from each routed VLAN and require at least 90% of the slowest negotiated endpoint link without material loss or router CPU saturation; resolve and reach the gateway DNS service from VLANs 10, 20, and 100; resolve `10.1.30.53` over both UDP and TCP 53 from a verified road-warrior client; reach TCP/22 and TCP/443 from VLAN 10 and VLAN 100 management hosts; establish both WireGuard listeners from their WAN peers; reach the Kubernetes VIP and the SNMP request path from the worker VLAN; submit SMTP over TCP/587 from printer `10.1.10.250` to relay VIP `10.1.30.58`; verify trusted LAN egress and the existing WAN destination-NAT service; and confirm that other printer-to-VLAN traffic, SMTP relay access from an unapproved source, an unapproved VLAN-to-VLAN connection, a road-warrior connection to a non-DNS Kubernetes VIP, a WAN connection without destination NAT, an unknown TCP/179 source, and an unknown WireGuard source are denied. Record only pass/fail, source class, destination class, throughput, packet-loss, CPU, and the final managed rule order; never record credentials or raw API responses.

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

The gateway permits UDP/161 from the Kubernetes worker VLAN `10.1.20.0/24` to Synology at `10.1.100.10`, and the imported baseline contains the corresponding enabled reply rule. The exact rule and established/related handling must be checked after apply before a separate cleanup plan removes the stateless reply exception.

## Synology routed access

The inventory places Synology on `ether3`, untagged VLAN 100, at `10.1.100.10`. VLAN 100 is a layer-2 path and does not traverse the forward chain; VLANs 10, 20, 101, and 102 are routed paths. OpenTofu derives each exact rule's source subnet, ingress interface name, and `vlan100` egress interface name from the authoritative VLAN inventory. The four Synology rules precede the inter-VLAN, WAN-inbound, and terminal-unmatched drops. Established sessions are still FastTracked after the initial allow, so the exception does not add per-packet logging or a throughput limiter.

The user-created broad `lan-to-nas` rule is explicitly disabled and state-owned as retired policy. The move sequence places it and the broad VLAN 10 rules after `sk-firewall/forward/drop-unmatched`, so they cannot provide an allow path while remaining available for counter-backed cleanup. The four exact Synology rules above are the coded replacement.

Do not add VLAN 101 or VLAN 102 to the broad `LAN` interface list to solve this path. The implementation uses `sk-internal-vlans` only for DHCP and the Kubernetes service-VIP boundary, while exact Synology rules grant only the required NAS destination access; general WAN egress and broad inter-VLAN access remain outside that list.

The VLAN 100 DHCP pool starts at `10.1.100.11` so the static Synology address `10.1.100.10` cannot be allocated dynamically. The read-only baseline found one complete ARP owner for the NAS and no existing DHCP lease; repeat this check during the performance acceptance test.

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
