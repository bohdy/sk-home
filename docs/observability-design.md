# Observability design

This file records the current implementation plan for Home Infrastructure Observability in the `sk-talos` cluster. It consolidates the settled design decisions before Kubernetes manifests are introduced.

## Goal

Home Infrastructure Observability is one cluster-hosted platform that collects and correlates operational signals from active home infrastructure: Kubernetes workloads, cluster nodes, network devices, and core services.

The first version should prioritize metrics, logs, syslog, SNMP, and synthetic checks. Traces are deferred until there are instrumented applications producing spans.

## Non-goals

The first implementation does not include application tracing, deep UniFi API integration, per-client DNS analytics, NetFlow or sFlow collection, long-term event correlation, formal SLOs, external alert notifications, or automated backup/snapshot workflows.

DNS query log shipping is disabled by default because DNS logs expose client behavior.

## Dependencies

Observability storage depends on generic cluster storage being validated first. The storage design is documented in `docs/storage-design.md`.

The expected storage path is Synology CSI with explicit-only iSCSI `ReadWriteOnce` volumes. VictoriaMetrics, VictoriaLogs, and Grafana should not be deployed with PVCs until the `synology-iscsi-retain` StorageClass passes live bind, mount, read/write, cross-node failover, expansion, and retained-volume validation.

DNS observability also depends on adding an internal CoreDNS metrics `ClusterIP` Service when observability scraping is introduced. CoreDNS metrics must remain cluster-internal and restricted to observability scraping.

## Components

Use Grafana as the primary UI with VictoriaMetrics-family backends for v1 storage.

The v1 component set is:

- Grafana for dashboards and exploration.
- VictoriaMetrics Operator for VictoriaMetrics-family resources.
- `VMSingle` for metrics storage.
- `VLSingle` for log and syslog storage.
- `VMAgent` for metrics scraping.
- `VLAgent` for logs if it handles Kubernetes logs and syslog cleanly.
- `VMAlert` and `VMRule` for alert evaluation.
- kube-state-metrics and node exporter for Kubernetes and node visibility.
- blackbox exporter for synthetic checks.
- SNMP exporter for MikroTik metrics.
- A syslog receiver for network-device syslog.

Use VictoriaMetrics-native collection components where they fit. Add Grafana Alloy, OpenTelemetry Collector, Vector, or another collector only for concrete gaps such as syslog parsing, Kubernetes log enrichment, or routing that the Victoria-native agents cannot handle well.

Use single-node VictoriaMetrics-family storage in v1. Defer clustered VictoriaMetrics or VictoriaLogs until write volume, availability needs, or retention requirements exceed the single-node path.

## Flux layout

Deploy v1 through Flux with a mixed model: Helm releases for large vendor components or operators when they materially improve lifecycle management, and plain YAML for local wiring, scrape resources, alert rules, dashboards-as-config, exporters, NetworkPolicy, and small services where direct reviewability matters more.

Keep generic storage separate from observability. The intended component order is:

1. `storage-synology-csi` as a generic infrastructure component, after `cluster-policy` and Cilium.
2. `observability-foundation` for namespace and shared policy.
3. `victoriametrics-operator` for the operator install.
4. `observability-storage` for `VMSingle` and `VLSingle`.
5. `observability-collection` for agents, exporters, scrape configs, syslog receivers, and event collection.
6. `observability-ui` for Grafana, datasources, and dashboards.
7. `observability-alerting` for VMAlert rules and alert visibility.
8. `observability-access` for Cloudflare Tunnel and Access integration when that follow-up starts.

`observability-storage` depends on the generic cluster storage component being validated.

Pin images by immutable digest for plain manifests. For Helm-managed components, pin Helm chart versions and app versions at minimum, and use image digest overrides where the chart supports them cleanly without brittle values.

## Storage and retention

Use persistent volumes from day one for VictoriaMetrics, VictoriaLogs, and Grafana.

Initial PVC sizing:

- `VMSingle`: 20-50 Gi
- `VLSingle`: 20-50 Gi
- Grafana: 2-5 Gi

Collectors and exporters should normally stay ephemeral, using only local buffers when needed. Do not introduce shared NFS storage for collectors unless a specific component requires durable shared files.

Retention targets:

- Metrics: 30 days
- General Kubernetes and application logs: 7 days
- Kubernetes events: 7 days
- Network-device syslog: 14 days
- DNS query logs: disabled by default; if enabled later, 24-72 hours unless privacy, access control, and disk sizing are revisited

## Collection scope

The v1 target boundary includes Kubernetes cluster health, Cilium health, DNS metrics and synthetic checks, observability self-monitoring, node and system metrics, MikroTik SNMP plus syslog, UniFi syslog first, and blackbox checks for Grafana, DNS, public recursion, WAN reachability, and selected internal records.

Kubernetes metrics should start with safe sources: kube-state-metrics, kubelet/cAdvisor where available, node exporter, and Cilium. Defer direct scraping of API server, controller-manager, scheduler, and etcd metrics unless Talos and Kubernetes expose those endpoints cleanly without weakening control-plane security.

Use Kubernetes and node-level exporters for Talos node visibility in v1. Defer Talos API-specific metrics or log collection until a later pass identifies concrete gaps.

Include lightweight Kubernetes event collection if the VictoriaLogs or collector path supports it cleanly.

For MikroTik metrics, prefer SNMPv3. Allow SNMPv2c temporarily only if the community string is secret-managed, access is restricted to observability scraper source addresses, MikroTik firewall policy blocks broad LAN access, and the temporary nature is documented.

Use SNMP and syslog before credentialed network-device API polling. Avoid UniFi API credentials in v1 unless there is a clear observability gap.

NetFlow or sFlow collection is a desired future capability, but it is deferred to its own design branch.

## Synthetic checks

Use blackbox exporter for v1 synthetic checks, scraped by `VMAgent`.

Initial probes should include:

- Grafana internal HTTP.
- DNS VIP UDP/TCP checks where supported cleanly.
- `dns.bohdal.name`.
- `gw.bohdal.name`.
- Reverse PTR checks for `10.1.30.53` and `10.1.100.1`.
- `www.bohdal.name`.
- `example.com`.
- A WAN/public endpoint check.
- ICMP reachability to `8.8.8.8` as an external network reachability signal, not DNS health.

Run v1 synthetic checks from inside the cluster only. Keep manual LAN smoke tests for DNS and defer a dedicated LAN probe location until path-specific client reachability checks justify another host or agent lifecycle.

## Syslog

Syslog ingestion should prefer TCP where network devices support it, with UDP available as a fallback.

Expose syslog ingestion through a stable Cilium LoadBalancer VIP from the `10.1.30.0/24` service pool. Reserve `10.1.30.54` for syslog ingestion if it is free, separate from the DNS VIP at `10.1.30.53`.

Use only `syslog.internal.bohdal.name` as the v1 syslog target name. Do not add `log.internal.bohdal.name` because `log` is ambiguous across syslog, Kubernetes logs, VictoriaLogs, and future flow logs.

Restrict syslog access to expected network-device subnets through router/firewall policy and Kubernetes NetworkPolicy where applicable.

## DNS and access names

Use `internal.bohdal.name` as the internal-only DNS namespace for direct LAN service names. Use explicit records only; do not add a wildcard record for `*.internal.bohdal.name` by default.

When the corresponding services exist, add:

- `syslog.internal.bohdal.name A 10.1.30.54`
- `grafana.internal.bohdal.name A 10.1.30.55`
- `54.30.1.10.in-addr.arpa PTR syslog.internal.bohdal.name.`
- `55.30.1.10.in-addr.arpa PTR grafana.internal.bohdal.name.`

Do not add these records before the service VIPs are allocated and reachable.

The final Grafana naming model is:

- `grafana.bohdal.name`: canonical Cloudflare Access protected hostname for normal LAN and remote use.
- `grafana.internal.bohdal.name`: direct LAN break-glass hostname protected by Grafana login plus trusted-network controls.

Use a stable internal Cilium LoadBalancer VIP for the Grafana break-glass path only if it can be secured in the same change. Reserve `10.1.30.55` if it is free.

Do not introduce a general ingress controller only for v1 observability. Expose only Grafana, have Cloudflare Tunnel target Grafana's internal HTTP service or a minimal direct service path, and keep VictoriaMetrics, VictoriaLogs, exporters, and collector endpoints cluster-internal.

## Security

Use one shared `observability-system` namespace for the v1 observability control plane unless a component has a strong reason to live elsewhere. Scrape targets may remain in their source namespaces.

Use restricted-by-default Pod Security Admission and pod security settings where images support them. Prefer non-root execution, read-only root filesystems, RuntimeDefault seccomp, dropped capabilities, and no service account token unless a component needs Kubernetes API access.

Use default-deny NetworkPolicy in `observability-system`, staged with component manifests so the stack does not deadlock. Explicitly allow only required paths:

- Scrapers to targets.
- Grafana to VictoriaMetrics and VictoriaLogs.
- Collectors to storage endpoints.
- Syslog ingress from approved network-device subnets to the syslog VIP.
- Blackbox egress to approved probe targets.
- DNS egress where needed.
- Kubernetes API access only for components that need discovery or event collection.

Secrets such as Grafana admin credentials, SNMP communities, SNMPv3 credentials, and any future device API credentials must come from the repository secret-management path. Do not commit plaintext secrets or expose them in logs.

## Labels and fields

Use a minimal v1 metrics label policy. Prefer stable labels such as `namespace`, `pod`, `node`, `app`, `service`, `job`, `instance`, `device`, `interface`, `probe`, and `target`.

Use a minimal v1 log field taxonomy. Prefer stable fields such as `source_type`, `namespace`, `app`, `pod`, `node`, `device`, `facility`, `severity`, and `collector`.

Avoid using high-cardinality or sensitive values as primary labels, stream fields, or routing fields unless the storage and privacy impact is explicit. Examples include client IP, DNS query name, URL paths with IDs, MAC address, arbitrary client hostname, full message, request ID, and trace ID.

## Grafana

Treat Git as the source of truth for Grafana datasources, dashboards, folders, and supported provisioning. Grafana UI edits are acceptable for exploration, but durable dashboards and configuration should be committed back to Git.

The Grafana PVC should hold runtime state rather than become the authoritative dashboard store.

Use a small curated dashboard set in v1 and commit every dashboard JSON that deployment depends on. Upstream or community dashboards may be used as references or imported starting points, but runtime provisioning should not depend on live dashboard IDs.

Initial dashboards should cover:

- Kubernetes cluster health.
- Node resources.
- Cilium/BGP networking.
- DNS through Blocky/CoreDNS plus synthetic checks.
- VictoriaMetrics and VictoriaLogs self-monitoring.
- MikroTik metrics.
- Syslog overview.

## Alerts

Keep v1 alert notifications internal only. Use VMAlert and Grafana dashboards to surface alerts, but do not wire external push, email, or chat notifications until alert rules are proven useful and low-noise.

Initial high-signal alerts:

- VictoriaMetrics or VictoriaLogs unavailable.
- Grafana unavailable.
- DNS synthetic check failure.
- No ready Blocky/CoreDNS pods.
- Kubernetes node not ready.
- PVC nearing full.
- Syslog receiver unavailable.
- Blackbox WAN ICMP check to `8.8.8.8` failing.

Avoid recording rules in v1 unless a dashboard or alert clearly needs one. Start with raw VictoriaMetrics queries, then add recording rules later for repeated expensive queries or stable SLI-style derived metrics.

## Validation

Before treating v1 observability as ready, validate:

- Generic Synology CSI storage is already validated according to `docs/storage-design.md`.
- `VMSingle`, `VLSingle`, and Grafana all use explicit PVCs on the validated StorageClass.
- Grafana can read VictoriaMetrics and VictoriaLogs datasources.
- kube-state-metrics and node exporter metrics are visible.
- Cilium metrics are visible where exposed.
- Blocky metrics are scraped from the internal metrics service.
- CoreDNS metrics are scraped through the new internal metrics service.
- DNS synthetic checks pass for internal A records, PTR records, public recursion, and DNS VIP paths.
- ICMP check to `8.8.8.8` reports WAN reachability.
- Syslog can be received on `10.1.30.54` over TCP where supported and UDP as fallback.
- MikroTik SNMP metrics are scraped through the accepted SNMP version and access restrictions.
- Grafana is reachable through the secured internal break-glass path when that VIP is implemented.
- Default-deny NetworkPolicy does not block required observability paths.
- No DNS query logs are shipped unless a later privacy and retention decision explicitly enables them.
