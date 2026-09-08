# Gateway firewall baseline review

This document records the complete live RouterOS firewall baseline, the implemented OpenTofu policy, and the remaining acceptance checks. It is an audit and implementation record; it does not authorize or perform a RouterOS apply.

## Baseline and ownership

The read-only inventory workflow run [33994757629](https://github.com/bohdy/sk-home/actions/runs/33994757629) captured the gateway from `main` commit `80ff8e2ff84bb0cc24ee10dceaa52cf7a501c6f7` on 2026-09-05. A follow-up read-only RouterOS audit confirmed 29 `input` and 32 `forward` IPv4 filter rules, three IPv4 NAT rules, one IPv4 raw rule, three IPv4 mangle rules, zero bridge-filter rules, 26 IPv6 filter rules, one IPv6 NAT rule, one IPv6 mangle rule, and nine IPv6 firewall address-list entries.

All 61 live IPv4 filter rules and the other 44 live firewall-table/address-list rows are now represented by the `firewall_policy` maps or named resources in `variables.tf` and `firewall.tf`. The rows that were previously outside OpenTofu ownership were imported into the existing remote state under stable resource addresses. A fresh read-only ID comparison found exact state/live matches for every audited table: 61 IPv4 filters, 3 IPv4 NAT, 1 IPv4 raw, 3 IPv4 mangle, 26 IPv6 filters, 1 IPv6 NAT, 1 IPv6 mangle, and 9 IPv6 address-list entries.

The move resources now express explicit desired order for IPv4 filters, IPv4 NAT, and IPv6 filters. Data-source ownership checks fail if the live counts for IPv4 mangle, IPv6 filter, IPv6 NAT, or IPv6 mangle diverge from the declared maps; the post-import state/live audit also compares exact IDs for every table. RouterOS's provider has no raw-table data source, so the single generated raw counter row is state-owned and checked by every trusted inventory run; it is deliberately never moved. Comment matching is not used as an ownership shortcut.

The current targeted hardening plan reports 23 additions, 10 in-place changes, and 0 deletions. It creates the dedicated internal-VLAN interface boundary, five internal-network address-list entries, one missing VLAN 10 management entry, four exact routed Synology rules, ownership checks, and the IPv6 filter/NAT ordering resources; it disables the five broad legacy VLAN/NAS rules and updates the Kubernetes service-VIP, DHCP, WireGuard destination boundary, and filter ordering. The live gateway has not been changed; this plan is review evidence only.

The current state/live identity audit covers these tables:

| RouterOS table | Live rows | State rows | Ownership disposition |
| --- | ---: | ---: | --- |
| IPv4 filter (`input` + `forward`) | 61 | 61 | Declarative resources plus strict filter move preconditions. |
| IPv4 NAT | 3 | 3 | Declarative resources plus strict NAT move precondition. |
| IPv4 raw | 1 | 1 | Generated FastTrack counter row adopted and never moved; the provider lacks a raw data source. |
| IPv4 mangle | 3 | 3 | Generated FastTrack counter rows adopted, never moved, and count-checked. |
| Bridge filter | 0 | 0 | The provider data source is checked and the plan fails closed if a bridge-filter row appears. |
| IPv6 filter | 26 | 26 | Declarative resources, exact order, and strict data-source ownership check. |
| IPv6 NAT | 1 | 1 | Declarative resource and count-checked ownership. |
| IPv6 mangle | 1 | 1 | Declarative resource and count-checked ownership. |
| IPv6 firewall address list | 9 | 9 | Declarative `bad_ipv6` entries adopted. |

The import audit also found two stale state-only instances for the active WireGuard peer address-list rows under an obsolete resource address. Those two state entries were removed without a RouterOS delete; the live rows remain owned by the current `routeros_ip_firewall_addr_list.adopted` map.

The inventory relevant to the Synology path is:

| Segment | Gateway or port | Relevant fact |
| --- | --- | --- |
| VLAN 10 | `10.1.10.1/24` | Trusted LAN, tagged on the switch uplinks and untagged on the local access ports. |
| VLAN 20 | `10.1.20.1/24` | Kubernetes worker VLAN. |
| VLAN 100 | `10.1.100.1/24` | Synology is `10.1.100.10`; `ether3` is an untagged VLAN 100 bridge port. |
| VLAN 101 | `10.1.101.1/24` | Routed VLAN, not currently in the `LAN` interface list. |
| VLAN 102 | `10.1.102.1/24` | Routed VLAN, not currently in the `LAN` interface list. |
| Kubernetes service VIPs | `10.1.30.0/24` | Cilium-advertised `/32` VIPs, including internal DNS at `10.1.30.53`; all addressed VLANs receive this resolver through DHCP. |

VLAN 100 clients reach the Synology at layer 2 and do not traverse the IPv4 forward chain. VLANs 10, 20, 101, and 102 use the routed path and do traverse it. The implemented policy grants those four routed source VLANs exact access to `10.1.100.10`; VLAN 100 remains local-switching access.

## Implemented desired order

The import remains complete: all captured firewall-table rows stay represented in code and state. The following order is the hardening contract that the saved plan would apply. Imported legacy and default IPv4 filter rules that are redundant or broad are retained after the terminal deny rules until their counters and operational purpose justify a separate deletion plan; they cannot match in that position. RouterOS-generated FastTrack counter rows remain at their generated positions and are not passed to the provider move endpoint.

The input chain places established/related handling, invalid-state protection, loopback, DHCP from the dedicated `sk-internal-vlans` interface list, DNS, ICMP, IPsec, BGP, SNMP, and management before the canonical terminal drop. The active runner and WireGuard handshake rules are also before that drop. The old VLAN 10 management/ping rules are now disabled and remain owned after the terminal drop alongside the other imported legacy/default rules.

The forward chain places IPsec policy handling before FastTrack, then established/related and invalid-state handling, exact Synology rules for VLANs 10, 20, 101, and 102, trusted-LAN WAN egress, active site/WAN/WireGuard paths, Kubernetes service VIP access from the dedicated internal interface and address-list boundaries, WireGuard DNS, SMTP, SNMP, the exact Kubernetes-to-Proxmox API exception, explicit management exceptions, destination NAT, and the inter-VLAN/WAN/unmatched terminal drops. The general Kubernetes VIP rule excludes the printer-only SMTP VIP, and the road-warrior LAN rule excludes the full Kubernetes VIP range so the dedicated DNS rules remain meaningful. The imported `lan-to-nas`, broad VLAN 10-to-VLAN 100 rules, diagnostic passthrough, and duplicate/default forward rules remain represented after the terminal drop; the generated FastTrack counter row is state-owned but not moved.

This ordering addresses the original performance concern: a new routed Synology flow is admitted by an exact rule, while subsequent established traffic can encounter FastTrack before ordinary accepts. The rule-order change alone is not a throughput proof; the acceptance tests below remain required.

## Complete input-chain review

The order below is the current live order within the `input` chain. “Implemented disposition” describes the desired post-plan behavior; the live order remains unchanged until an approved production apply.

| Order | Live comment or identity | Current effect and review | Implemented disposition |
| ---: | --- | --- | --- |
| 1 | `Allow VLAN10 router management` | Allows TCP/22, 80, and 443 from all of VLAN 10 to the router. It overlaps the later management and SSH rules and includes unencrypted HTTP. | Disable in place and retain as imported ownership after the terminal drop; the canonical management rule permits only TCP/22 and 443 from the explicit VLAN 10 and VLAN 100 source list. |
| 2 | `Allow VLAN10 router ping` | Allows ICMP from all of VLAN 10 and overlaps the trusted-ICMP policy. | Disable in place and retain after the terminal drop; the canonical trusted-ICMP rule remains the active VLAN 10/20/100 gateway-ping path. |
| 3 | `sk-firewall/input/accept-established-related` | Canonical connection-tracking allow. It is correctly coded but is late in the current live order. | Move to the start of the canonical input policy. |
| 4 | `sk-firewall/input/drop-invalid` | Canonical invalid-state drop. | Keep and move next to the connection-tracking rules. |
| 5 | `sk-firewall/input/allow-icmp-trusted` | Allows ICMP from the `LAN` interface list, which covers VLANs 10, 20, and 100 but not VLANs 101 and 102. | Keep before the terminal drop; VLANs 101 and 102 remain intentionally unable to ping the gateway through this broad rule. |
| 6 | `sk-firewall/input/allow-loopback` | Standard loopback exception for `127.0.0.1`. | Keep. |
| 7 | `sk-firewall/input/allow-dhcp` | Allows trusted-interface DHCP client traffic from UDP/68 to UDP/67, but the live `LAN` list excludes VLANs 101 and 102 even though both have DHCP scopes in the inventory. | Update in place to the dedicated `sk-internal-vlans` interface list, which includes every addressed VLAN without broadening the general LAN policy. |
| 8 | `sk-firewall/input/allow-dns-udp` | Allows trusted-interface DNS over UDP/53. VLANs 101 and 102 use the Kubernetes DNS VIP supplied by DHCP, not the gateway address. | Keep on the existing `LAN` boundary; the internal-VLAN forward rule owns access to the Kubernetes DNS VIP. |
| 9 | `sk-firewall/input/allow-dns-tcp` | Allows trusted-interface DNS over TCP/53. VLANs 101 and 102 use the Kubernetes DNS VIP supplied by DHCP, not the gateway address. | Keep with the UDP rule; do not add the camera/AP VLANs to the gateway DNS boundary without a separate requirement. |
| 10 | `sk-firewall/input/allow-ipsec-esp` | Allows IPsec ESP without an interface restriction. | Keep only while an active IPsec peer requires it; verify counters and peer inventory. |
| 11 | `sk-firewall/input/allow-ipsec-handshake` | Allows UDP/500 and UDP/4500 without an interface restriction. | Keep only while an active IPsec peer requires it; bind to the expected WAN path if RouterOS permits the required design. |
| 12 | `sk-firewall/input/allow-kubernetes-bgp` | Allows TCP/179 from the declared Kubernetes node address list on VLAN 20. | Keep; verify the node inventory remains the source of truth. |
| 13 | `sk-firewall/input/allow-snmp-monitoring` | Allows UDP/161 from `10.0.0.0/8`. This covers the Kubernetes pod source range used by the SNMP exporter as well as internal node networks; the source is intentionally broader than a single VLAN until the monitoring egress identity is made stable. | Keep unchanged and document the pod-network dependency; the disabled `10.42.0.0/16` legacy rule stays after the terminal drop. |
| 14 | `sk-firewall/input/allow-management` | Allows TCP/22 and TCP/443 from the managed source address list, currently the VLAN 100 subnet in live state. | Keep as the canonical management path and add the verified VLAN 10 source entry; remove port 80 from the active canonical path. |
| 15 | `sk-firewall/input/allow-github-actions-runner-https` | Allows the DHCP-reserved runner `10.1.20.200` to reach gateway `10.1.100.1` over TCP/443 from VLAN 20. | Keep before the terminal drop; the reservation is present in `dhcp.auto.tfvars` and the rule is now explicitly owned. |
| 16 | `wireguard` | Allows UDP/51820 from the `WAN` interface list. | Keep if this is the road-warrior listener. |
| 17 | `Allow WireGuard site-to-site handshake` | Allows UDP/51280 from the `WAN` interface list. | Keep if the site-to-site peer is active and documented. |
| 18 | `sk-firewall/input/drop-unmatched` | Terminal input drop for packets not matching an earlier rule. | Keep as the only terminal input deny. |
| 19 | `LAN k3s` | Disabled rule for UDP/161 from `10.42.0.0/16`, a pod range not present in the gateway interface inventory. It is also after the terminal drop and therefore unreachable in the current order. | Retain disabled and after the terminal drop; the active monitoring rule is the explicitly reviewed broad path above. |
| 20 | `SNMP LAN IN` | Disabled rule for UDP/161 from every interface in `LAN`. It is after the terminal drop and unreachable. | Retain disabled and after the terminal drop as imported ownership until a counter-backed cleanup removes it. |
| 21 | `SSH LAN IN` | Disabled rule for TCP/22 from every interface in `LAN`. It is after the terminal drop and unreachable. | Retain disabled and after the terminal drop; use the canonical management rule. |
| 22 | `Allow WireGuard roadwarrior` | Disabled rule for UDP/51820 from any source, with no WAN restriction. It is after the terminal drop and unreachable, and duplicates the named road-warrior rule. | Retain disabled and after the terminal drop; the active listener remains restricted to `WAN`. |
| 23 | Unnamed `ipsec-esp` | Allows IPsec ESP. It is after the terminal drop and unreachable, and duplicates the earlier IPsec rule. | Retain after the terminal drop as imported ownership until active-peer counters justify deletion. |
| 24 | Unnamed UDP/500,4500 | Allows IPsec negotiation. It is after the terminal drop and unreachable, and duplicates the earlier handshake rule. | Retain after the terminal drop as imported ownership until active-peer counters justify deletion. |
| 25 | `defconf: accept established,related,untracked` | Default RouterOS established-session allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical connection-tracking rule is earlier. |
| 26 | `defconf: drop invalid` | Default RouterOS invalid-state drop. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical invalid-state rule is earlier. |
| 27 | `defconf: accept ICMP` | Default RouterOS ICMP allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the trusted ICMP rule is earlier and boundary-limited. |
| 28 | `defconf: accept to local loopback (for CAPsMAN)` | Default RouterOS loopback allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical loopback rule is earlier. |
| 29 | `defconf: drop all not coming from LAN` | Default RouterOS non-LAN terminal drop. It is after the canonical terminal drop and unreachable. | Retain after the terminal drop as imported ownership; the canonical terminal input drop is the earlier boundary. |

## Complete forward-chain review

The order below is the current live order within the `forward` chain. The first four rules are particularly relevant to the Synology performance question; the implemented disposition describes the desired order after the saved plan.

| Order | Live comment or identity | Current effect and review | Implemented disposition |
| ---: | --- | --- | --- |
| 1 | `lan-to-nas` | Accepts every routed protocol to `10.1.100.10` from any source. It is before FastTrack, so matching Synology packets are accepted before reaching the current FastTrack rule. This is a credible cause of lower routed NAS throughput when the gateway CPU is the bottleneck. | Disable in place and retain as imported ownership after the terminal drop; add exact source VLAN/interface rules for VLANs 10, 20, 101, and 102. FastTrack is now earlier than those exact new-flow accepts. |
| 2 | `Allow VLAN10 to VLAN100 management` | Allows TCP/22, 80, 443, 445, 5000, and 5001 from all of VLAN 10 to all of VLAN 100. It overlaps `lan-to-nas` for the Synology and exposes every VLAN 100 host. | Disable in place and retain after the terminal drop; the implemented exact Synology rules cover the NAS requirement without exposing the entire VLAN 100 subnet. |
| 3 | `Allow VLAN10 to VLAN100 ping` | Allows ICMP from all of VLAN 10 to all of VLAN 100. It overlaps `lan-to-nas` for the Synology and is broad for the rest of VLAN 100. | Disable in place and retain after the terminal drop; the exact Synology rule covers routed NAS traffic and VLAN 100 local-L2 behavior is unchanged. |
| 4 | `special dummy rule to show fasttrack counters` | Dynamic passthrough rule with no match restriction. It is not an allow rule but makes the policy harder to understand. | Retain as a RouterOS-generated, state-owned diagnostic row; exclude it from the move sequence and investigate its purpose before any deletion. |
| 5 | `sk-firewall/forward/fasttrack-established-related` | Canonical FastTrack rule, but it is after the broad NAS and VLAN 10 rules. | Move after the two explicit IPsec policy exceptions and before ordinary established/related and new-flow accepts. |
| 6 | `sk-firewall/forward/accept-established-related` | Canonical established-session allow. | Keep immediately after FastTrack. |
| 7 | `sk-firewall/forward/drop-invalid` | Canonical invalid-state drop. | Keep near the connection-tracking rules. |
| 8 | `sk-firewall/forward/allow-ipsec-in` | Allows inbound IPsec-policy traffic. | Move before FastTrack; MikroTik requires established/related IPsec bypass rules ahead of FastTrack. |
| 9 | `sk-firewall/forward/allow-ipsec-out` | Allows outbound IPsec-policy traffic. | Move before FastTrack; verify counters and the active peer design after apply. |
| 10 | `sk-firewall/forward/allow-trusted-lan-to-wan` | Allows all traffic from the `LAN` interface list to the `WAN` interface list. VLANs 101 and 102 are not in `LAN` and do not receive this path. | Keep before the terminal drops; the dedicated internal interface list is deliberately not substituted for `LAN`, so VLANs 101 and 102 do not gain general WAN egress. |
| 11 | `sk-firewall/forward/allow-site-to-site` | Allows all traffic from `10.1.0.0/16` to `10.2.0.0/16`. | Keep only if the site-to-site route and peer are active; narrow to required source and destination segments if possible. |
| 12 | `KNOWN WAN` | Allows any protocol from address list `ACCD` arriving on `WAN`, without a destination or service restriction. | Review the NAT and peer purpose; narrow to the intended destination and service instead of allowing the entire routed path. |
| 13 | `sk-firewall/forward/allow-wireguard-roadwarrior-to-trusted-lan` | Allows road-warrior address-list members from `wg-roadwarrior` to every destination in `LAN`, including the Kubernetes service-VIP range. | Preserve the existing trusted-LAN access while excluding `10.1.30.0/24`; the dedicated UDP/TCP DNS rules then remain the only road-warrior path to Kubernetes VIPs. Review the remaining broad trusted-LAN access separately. |
| 14 | `sk-firewall/forward/allow-wireguard-site-to-site-to-trusted-lan` | Allows all `10.2.0.0/16` traffic from `wireguard1` to every destination in `LAN`. | Keep if required for the site; narrow the destination boundary if the peer needs only selected services. |
| 15 | `sk-firewall/forward/allow-kubernetes-service-vips` | Allows all trusted-LAN traffic to the Kubernetes service VIP address list, so the live rule excludes VLANs 101 and 102 even though their DHCP scopes advertise `10.1.30.53`; it also overlaps the printer-specific SMTP exception. | Update in place to require both the exact internal VLAN address list and the dedicated internal-VLAN interface list, while excluding relay VIP `10.1.30.58`; this makes Kubernetes services and DNS reachable from VLANs 10, 20, 100, 101, and 102 without adding those VLANs to `LAN`, while SMTP remains printer-only. |
| 16 | `sk-firewall/forward/allow-wireguard-kubernetes-dns-udp` | Allows road-warrior address-list members to Kubernetes DNS VIP `10.1.30.53` over UDP/53. | Keep if required; retain the exact destination and port restriction. |
| 17 | `sk-firewall/forward/allow-wireguard-kubernetes-dns-tcp` | Allows road-warrior address-list members to Kubernetes DNS VIP `10.1.30.53` over TCP/53. | Keep if required; retain the exact destination and port restriction. |
| 18 | `sk-firewall/forward/allow-smtp-relay-from-printer` | Allows printer `10.1.10.250` to relay VIP `10.1.30.58` over TCP/587. | Keep after verifying the DHCP reservation or static ownership and the relay's advertised VIP. |
| 19 | `Allow Kubernetes worker VLAN to poll Synology SNMP` | Allows VLAN 20 to reach Synology UDP/161. This is narrow and matches the monitoring requirement. | Keep if the worker source and static Synology address remain current. |
| 20 | `Allow Synology SNMP replies to Kubernetes worker VLAN` | Allows Synology UDP/161 replies to VLAN 20. It is enabled in the live baseline; established/related handling may make it redundant, but UDP reply behavior must be verified before removal. | Keep for the baseline; test counters and then decide whether stateful return handling makes it unnecessary. |
| 21 | `Allow Kubernetes worker VLAN to poll UniFi SNMP` | Allows VLAN 20 to poll UDP/161 across VLAN 102. | Keep if the worker is the authorized monitor; consider exact AP addresses after reservations are complete. |
| 22 | `Allow UniFi SNMP replies to Kubernetes worker VLAN` | Allows UDP/161 replies from VLAN 102 to VLAN 20. | Keep for the baseline; test stateful return handling before simplifying. |
| 23 | `Allow Kubernetes worker VLAN to Proxmox API` | No matching live rule exists, so Kubernetes-to-Proxmox TCP/8006 falls through to the inter-VLAN drop. | Add the exact `10.1.20.0/24` to `10.1.100.201:8006/tcp` allow before the terminal drops so the Proxmox exporter can scrape its API. |
| 24 | `sk-firewall/forward/allow-wan-dstnat` | Allows new WAN traffic that matched destination NAT. | Keep before the terminal drops, with the existing NAT-state condition and current NAT inventory review. |
| 25 | `sk-firewall/forward/drop-inter-vlan` | Drops unmatched traffic between trusted `LAN` interfaces. VLANs 101 and 102 are outside this interface-list policy. | Keep as a boundary; the required VLAN 101/102 and Kubernetes-to-Proxmox exceptions are explicit rules above, and all other traffic remains denied by the terminal policy. |
| 26 | `sk-firewall/forward/drop-wan-inbound` | Drops new WAN-to-LAN traffic that is not allowed by an earlier rule. | Keep as the intentional WAN terminal boundary. |
| 27 | `sk-firewall/forward/drop-unmatched` | Terminal forward drop. | Keep as the only terminal forward deny. |
| 28 | `defconf: accept in ipsec policy` | Default RouterOS inbound IPsec allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical IPsec rule is earlier and owned separately. |
| 29 | `defconf: accept out ipsec policy` | Default RouterOS outbound IPsec allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical IPsec rule is earlier and owned separately. |
| 30 | `defconf: fasttrack` | Default FastTrack rule. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical FastTrack rule is earlier in the managed policy, after the two IPsec exceptions. |
| 31 | `defconf: accept established,related, untracked` | Default established-session allow. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical established rule is now second. |
| 32 | `defconf: drop invalid` | Default invalid-state drop. It is after the terminal drop and unreachable. | Retain after the terminal drop; the canonical invalid-state rule is now third. |
| 33 | `defconf: drop all from WAN not DSTNATed` | Default WAN non-destination-NAT drop with `connection_nat_state = !dstnat`. It is after the terminal drop and unreachable. | Retain after the terminal drop with its NAT-state condition represented in code; the canonical WAN boundary is earlier. |

## NAT, raw, mangle, and IPv6 review

The imported baseline was not limited to IPv4 filter chains. These rows are part of the same ownership boundary and were reviewed before the targeted plan was regenerated.

### IPv4 NAT

| Live ID | Rule | Review and disposition |
| --- | --- | --- |
| `*3` | Disabled `dst-nat` from `10.1.102.0/24` to `10.1.20.222`, translated to `10.1.30.10`. | Retain disabled and state-owned; do not revive without a documented service requirement. |
| `*1` | Active `srcnat` masquerade out `WAN`, comment `defconf: masquerade`. | Preserve unchanged; this is required for trusted-LAN WAN egress. |
| `*2` | Active WAN TCP/32400 destination NAT to `192.168.100.10:32400`. | Preserve unchanged and verify the matching `forward/allow-wan-dstnat` path after apply. |

### IPv4 raw and mangle

The one raw row and three mangle rows are RouterOS-generated FastTrack counter passthrough rows with the comment `special dummy rule to show fasttrack counters`. They are adopted under stable resource addresses, ignored for provider-default drift, and never sent to a move endpoint. They are diagnostics, not allow/deny policy; the trusted inventory records their identities so a newly added raw or mangle row is visible during review.

### IPv6

The 26 IPv6 filter rows are fully represented in code and retain their live order: four custom WireGuard/BGP/source exceptions followed by the RouterOS default input and forward policy. The nine `bad_ipv6` address-list entries used by the default forward drops are also adopted. The disabled IPv6 NAT row and active IPv6 output packet-mark row are adopted without changing their current behavior.

Two IPv6 rows need explicit post-apply review even though this task preserves them: `SH` accepts traffic from `2001:718:2:40::70/128`, and the unnamed `wireguard1` input rule accepts all IPv6 traffic arriving from that interface. They may be intentional for the OPNsense/BGP design, but they should be narrowed or disabled in a separate reviewed change if the peer does not require general IPv6 access. The default IPv6 input/forward drops remain in code and order, so this review does not silently broaden IPv6 access while fixing the IPv4 Synology path.

## Internal reachability matrix

| Source network | Kubernetes VIPs and DNS | Synology `10.1.100.10` | Other intentional paths | General boundary |
| --- | --- | --- | --- | --- |
| VLAN 10 | Allowed through `sk-internal-vlan-networks` plus `sk-internal-vlans`; includes DNS VIP `10.1.30.53`. | Exact routed rule to the NAS host; the disabled VLAN 10 management and ping legacy rules no longer match before the terminal drop. | Router management TCP/22 and 443; trusted-LAN WAN egress; printer SMTP source when applicable. | No unrestricted access to other internal VLANs. |
| VLAN 20 | Allowed through the same explicit service boundary; includes Kubernetes DNS. | Exact routed rule to the NAS host. | BGP TCP/179 from declared nodes; SNMP polling paths; Proxmox API TCP/8006 from the exporter path; trusted-LAN WAN egress; runner-to-gateway HTTPS. | Inter-VLAN traffic remains denied unless an explicit service rule exists. |
| VLAN 100 | Allowed through the same explicit service boundary; DHCP advertises the Kubernetes DNS VIP. | Local layer-2 access through `ether3`; no forward-chain allow is required. | Router management TCP/22 and 443; trusted-LAN WAN egress; gateway DHCP/DNS/ICMP according to the existing LAN policy. | No new routed access is granted by the Synology rule set. |
| VLAN 101 | Allowed through the explicit service and interface boundaries; DHCP is now allowed and advertises Kubernetes DNS. | Exact routed rule to the NAS host. | DHCP only from the dedicated internal interface boundary unless another existing exact rule applies. | Not added to `LAN`; no general WAN egress or broad inter-VLAN access. |
| VLAN 102 | Allowed through the explicit service and interface boundaries; DHCP is now allowed and advertises Kubernetes DNS. | Exact routed rule to the NAS host. | SNMP reply path from the AP management subnet remains owned for worker polling. | Not added to `LAN`; no general WAN egress or broad inter-VLAN access. |
| WireGuard road-warrior | The existing trusted-LAN path remains, but its new destination exclusion removes the Kubernetes VIP range; only the exact UDP/TCP DNS rules reach `10.1.30.53`. | Existing WireGuard-to-LAN policy can reach VLAN 100; the new routed-VLAN rules are not a substitute for VPN policy. | Road-warrior handshake on WAN and exact peer address-list ownership. | Other Kubernetes VIPs are denied; the remaining broad trusted-LAN access is an existing separate policy decision and is not claimed as DNS-only. |

## Verification and remaining acceptance

1. The complete live baseline is imported: state/live IDs match for 61 IPv4 filters, 3 IPv4 NAT, 1 IPv4 raw, 3 IPv4 mangle, 26 IPv6 filters, 1 IPv6 NAT, 1 IPv6 mangle, and 9 IPv6 address-list entries.
2. The targeted plan contains 24 creates, 10 in-place updates, and 0 deletes or replacements. The workflow rejects any firewall artifact containing a delete or replacement before upload.
3. The plan places IPsec exceptions before FastTrack, creates exact Synology rules for routed VLANs 10, 20, 101, and 102, adds the exact Kubernetes-to-Proxmox API path, preserves VLAN 100 local-L2 access, allows DHCP on every addressed VLAN, constrains Kubernetes service VIP access to the dedicated internal interface and address-list boundaries, excludes the SMTP relay VIP from the general service rule, and excludes all Kubernetes VIPs from the broad road-warrior LAN rule.
4. The live gateway has not been changed by this task. After an approved production apply, run representative ICMP, TCP, and UDP Synology tests from VLANs 10, 20, 101, and 102 in both directions, verify VLAN 100 layer-2 access, and confirm that exact Synology and established/FastTrack counters increment without terminal-drop counters.
5. Run three 60-second, four-stream `iperf3` tests in both directions from each routed VLAN and require at least 90% of the slowest negotiated endpoint link without material loss or router CPU saturation. Record only pass/fail, source class, destination class, throughput, packet loss, CPU, and managed rule order.
6. Also verify Kubernetes VIP/DNS access from every addressed VLAN, gateway DHCP/DNS and management paths, BGP from all six declared nodes, worker-to-Synology and worker-to-UniFi SNMP, printer-to-relay SMTP, trusted WAN egress, existing WAN destination NAT, both WireGuard listeners, the preserved IPv6 peer paths, and denial of unknown WAN, inter-VLAN, BGP, WireGuard, and SMTP sources.
7. Only after the observation window and counter review should a separate cleanup plan delete the now-unreachable imported duplicates. Until then they remain fully coded and state-owned; generated counter rows remain observed and no audited live firewall-table identity is outside the declared ownership boundary.
