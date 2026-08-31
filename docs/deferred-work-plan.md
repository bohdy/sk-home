# Deferred Work Plan

This is the execution checklist for work intentionally deferred after the first observability release and the completed PR264 and state-migration cleanup tasks. Detailed design constraints remain in the linked documents; update this checklist when a task starts or reaches acceptance.

## Completed Prerequisites

- [x] Merge PR264, which fixes the selected-host Sankey query for ClickHouse 26.7.
- [x] Remove completed Cloudflare import scaffolding and the Proxmox phantom-ACL `removed` block.
- [x] Configure the WireGuard remote-access client to use Kubernetes DNS at `10.1.30.53`.

## Priority 0

- [ ] Resolve the RouterOS provider incompatibility affecting the worker BGP peer, then apply and verify the declarative peer through the production-gated workflow; do not use an imperative REST workaround. Track implementation in [issue #276](https://github.com/bohdy/sk-home/issues/276).
- [ ] Complete the focused WireGuard firewall contract, then adopt and verify declarative WireGuard peers in [issue #302](https://github.com/bohdy/sk-home/issues/302). The broader default-deny input and forward policy remains a later stage of [issue #301](https://github.com/bohdy/sk-home/issues/301).
- [x] Separate untrusted pull-request OpenTofu validation from trusted production planning and applying so PRs receive no infrastructure credentials and sensitive binary plans are not retained as ordinary artifacts.

## Priority 1

- [ ] Apply and live-validate the RouterOS DHCP change that advertises `10.1.30.53` on every relevant LAN scope, with UDP and TCP DNS smoke tests from each VLAN and a documented rollback.
- [ ] Reassess the Proxmox group `acl` lifecycle workaround after upgrading beyond provider `0.106.0`; remove it only after a live no-destroy plan and effective-permission verification.
- [ ] Diagnose RouterOS SNMPv2c compatibility without weakening the accepted SNMPv3 production path.
- [ ] Reset the Brother printer administrator password, confirm its read-only SNMPv2c profile, validate `system` and `printer_mib`, and enable its intermittent scrape without offline paging.
- [x] Prepare and live-validate UniFi Poller now that the controller migration is complete, if controller-level metrics are still needed beyond access-point SNMP. The Bitwarden-backed Secret was bootstrapped after the reviewed change reached `main`, the optional child Kustomization reconciled successfully, and the live exporter collected through the verified LAN TLS VIP without exposing credentials. VMAgent reported healthy UniFi targets, `unpoller_device_*` series were dropped to keep AP coverage SNMP-owned, VMAlert loaded the poller rule with no active alert, and the controller/client dashboard was provisioned. The exporter hashes client names and MAC addresses, and the scrape removes `mac`, `name`, `hostname`, and `ip` labels before storage, so stored client series retain aggregate/client-quality values without those identifying labels. The operator confirmed that the dedicated local `unifi-poller-api` account is endpoint-scoped and read-only; no credential values are recorded here.
- [ ] Define and implement automated Bitwarden-to-Kubernetes secret reconciliation only after reviewing the SDK-server and machine-token risks.
- [ ] Add a raw telemetry backup or snapshot strategy covering the retention and recovery requirements for VictoriaMetrics, VictoriaLogs, and ClickHouse.
- [ ] Add an external dead-man heartbeat and path-specific probes from a LAN host outside Kubernetes and the home internet failure domain.
- [ ] Add a CoreDNS metrics Service and scrape resource, or remove the unsupported CoreDNS panels from the DNS dashboard.
- [ ] Make OpenTofu provider lockfile policy intentional and consistent across every active stack, including supported CI platforms.
- [ ] Remove or implement the no-op `detect-changes` job in the OpenTofu workflow while preserving required check names and stack planning behavior.
- [ ] Expand repository validation to render all active Kustomize trees, validate schemas and CRDs where available, check generated SNMP output, scan rendered manifests for secrets without printing matches, and lint Markdown.
- [ ] Reconcile stale repository cleanup documentation so `README.md`, `AGENTS.md`, and historical acceptance records accurately describe the active repository.

## Priority 2

- [ ] Add switch or access-point telemetry for same-VLAN flow visibility, which the MikroTik gateway cannot provide.
- [ ] Add ClickHouse materialized views or rollups if dashboard query cost or retention pressure requires them.
- [ ] Revisit the Vector flow handoff topology if node-local file delivery becomes unreliable for the single-replica collector.
- [ ] Add sFlow or other NetFlow formats if non-IPFIX exporters are introduced.
- [ ] Revisit ClickHouse authentication if its exposure broadens beyond the current cluster-internal trust boundary.
- [ ] Add Klipper and Moonraker monitoring after confirming an exporter and endpoint-scoped read-only authentication.
- [ ] Add distributed tracing after applications emit useful OpenTelemetry spans.
- [ ] Revisit a pre-bundled Grafana image if runtime plugin installation becomes unreliable.
- [ ] Add workers or clustered VictoriaMetrics-family storage if availability requirements change.
- [ ] Return the DNS namespace to restricted Pod Security Admission after validating cap-free Blocky and CoreDNS images or an equivalent runtime strategy.

## References

- DNS decisions and validation requirements: `docs/dns-design.md`.
- Flow-specific follow-up design: `docs/flow-collection-design.md`.
- Observability architecture and non-goals: `docs/observability-design.md`.
- Rollout evidence and live acceptance history: `docs/observability-rollout.md`.
