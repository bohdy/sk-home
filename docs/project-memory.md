# Project memory

This file records operational facts and future-facing notes that should survive individual implementation threads. Keep entries concise, dated, and tied to concrete follow-up decisions.

## 2026-06-09 DNS bring-up

Flux bootstrap for the Talos cluster succeeded with Flux v2.8.8 under `kubernetes/flux/clusters/sk-talos`.

The LAN DNS design uses Blocky as the only client-facing resolver at `10.1.30.53` and CoreDNS as the internal split-DNS authority and DNS4EU DoT forwarder.

During live bring-up, the pinned upstream Blocky and CoreDNS images failed with `operation not permitted` when the DNS namespace used restricted Pod Security Admission and the containers set `allowPrivilegeEscalation: false` with `capabilities.drop: ["ALL"]`. The current working decision is to keep the `dns-system` namespace at baseline PSA while retaining non-root execution, read-only root filesystems, and RuntimeDefault seccomp. Returning DNS to restricted PSA needs a validated cap-free image strategy or another tested runtime approach.

Blocky v0.29 resolver entries use `[net:]host:[port]` syntax. The CoreDNS upstream must be `tcp+udp:coredns.dns-system.svc.cluster.local:53`, not URL-style `tcp+udp://...`.

Blocky special-use domain blocking must stay disabled while CoreDNS is the only upstream, otherwise private reverse zones return Blocky-generated NXDOMAIN responses before CoreDNS can answer LAN PTR records.

CoreDNS reached healthy state once the runtime constraints were relaxed. Blocky reached healthy state after the runtime fix and corrected upstream syntax; a live test showed successful resolution of `dns.bohdal.name` through CoreDNS.

## Observability Inputs

The accepted first scope for Home Infrastructure Observability is one cluster-hosted platform that collects and correlates operational signals from active home infrastructure: Kubernetes workloads, cluster nodes, network devices, and core services. The first version should prioritize metrics, logs, syslog, SNMP, and synthetic checks; traces should be deferred until there are actual instrumented applications producing spans.

Home Infrastructure Observability should be centered on Grafana as the primary UI while preferring VictoriaMetrics-family backends for storage. Prometheus-compatible metrics should be the metrics contract, VictoriaLogs should be the preferred v1 log and syslog backend, and Tempo should stay deferred until traces matter. Grafana Alloy remains an option for the collection layer if it materially simplifies Kubernetes, syslog, SNMP, and future OTLP collection.

VictoriaMetrics is the accepted v1 metrics backend. Use VictoriaMetrics Operator with a single-node `VMSingle` store, `VMAgent` for scraping, and `VMAlert` with `VMRule` resources for alert evaluation. Prefer VM-native scrape resources such as `VMServiceScrape` and `VMPodScrape`, while keeping Prometheus-compatible metrics as the contract for exporters and dashboards.

Use a minimal v1 metrics label policy. Prefer stable Prometheus-style labels such as `namespace`, `pod`, `node`, `app`, `service`, `job`, `instance`, `device`, `interface`, `probe`, and `target`; avoid custom high-cardinality labels such as client IP, DNS query name, URL paths with IDs, MAC address, arbitrary client hostname, or full message-derived fields unless the storage and privacy impact is explicit.

VictoriaLogs is the preferred v1 log and syslog backend. Use VictoriaMetrics Operator resources such as `VLSingle` and `VLAgent` when they fit the implementation, and keep Loki only as a fallback if VictoriaLogs has a concrete blocker around syslog ingestion, Kubernetes log collection, Grafana querying, retention, or operational maturity.

Use a minimal v1 log field taxonomy for VictoriaLogs. Prefer stable fields such as `source_type`, `namespace`, `app`, `pod`, `node`, `device`, `facility`, `severity`, and `collector`; avoid making client IP, DNS query name, MAC address, full message, request ID, or trace ID primary stream/routing fields unless the cardinality and privacy implications are explicitly accepted.

Use single-node VictoriaMetrics-family storage in v1: `VMSingle` for metrics and `VLSingle` for logs. Defer clustered VictoriaMetrics or VictoriaLogs until write volume, availability needs, or retention requirements exceed the single-node path.

Prefer VictoriaMetrics-native collection components where they fit. Use `VMAgent` for metrics, use `VLAgent` for logs if it handles Kubernetes logs and syslog cleanly, scrape SNMP and synthetic exporters through `VMAgent`, and add Grafana Alloy, OpenTelemetry Collector, Vector, or another collector only for concrete gaps such as syslog parsing, Kubernetes log enrichment, or routing that the Victoria-native agents cannot handle well.

Collector redundancy should come from pipeline shape, not shared storage. Use a DaemonSet-style collector for Kubernetes pod logs, consider two or more syslog receiver replicas behind a stable service or VIP with TCP preferred where devices support it, and keep metrics, SNMP, and blackbox scraping to one logical scraper unless a VictoriaMetrics deduplication strategy is deliberately configured. Collectors and exporters should normally stay ephemeral, using only local buffers when needed; do not introduce shared NFS storage for collectors unless a specific component requires durable shared files.

Syslog ingestion should prefer TCP where network devices support it, with UDP available as a fallback for devices that cannot send TCP syslog. If the selected receiver supports both cleanly, expose both protocols but configure devices to use TCP first.

Expose syslog ingestion through a stable Cilium LoadBalancer VIP from the `10.1.30.0/24` service pool so MikroTik, UniFi, and other devices have a stable destination. Reserve `10.1.30.54` for syslog ingestion if it is free, keep it separate from the DNS VIP at `10.1.30.53`, and restrict access to expected network-device subnets through router/firewall policy and Kubernetes NetworkPolicy where applicable.

Use conservative v1 retention defaults: 30 days for metrics, 7 days for general Kubernetes and application logs, 14 days for network-device syslog, and no DNS query log shipping by default. If DNS query logs are enabled later, keep them to 24-72 hours unless privacy, access control, and disk sizing are explicitly revisited.

Keep v1 alert notifications internal only. Use VMAlert and Grafana dashboards to surface alerts, but do not wire external push, email, or chat notifications until the first alert rules are proven useful and low-noise.

Include a tiny high-signal alert set in v1 while keeping notifications internal only. Initial alerts should cover VictoriaMetrics or VictoriaLogs unavailable, Grafana unavailable, DNS synthetic check failure, no ready Blocky/CoreDNS pods, Kubernetes node not ready, PVC nearing full, syslog receiver unavailable, and blackbox WAN ICMP check to `8.8.8.8` failing; defer noisy threshold alerts such as high CPU until real baselines exist.

Avoid recording rules in v1 unless a dashboard or alert clearly needs one. Start with raw VictoriaMetrics queries, then add recording rules later for repeated expensive queries or stable SLI-style derived metrics.

The v1 target boundary includes Kubernetes cluster health, Cilium health, DNS stack metrics and synthetic checks, observability self-monitoring, node and system metrics, MikroTik SNMP plus syslog, UniFi syslog first, and blackbox checks for Grafana, the DNS VIP, selected internal records, public recursion, and WAN/public endpoints. Defer per-client DNS analytics, deep UniFi API integration, NetFlow/sFlow collection, application tracing, long-term event correlation, and formal SLOs.

Use blackbox exporter for v1 synthetic checks, scraped by `VMAgent`. Initial probes should include Grafana internal HTTP, DNS VIP UDP/TCP checks where supported cleanly, `dns.bohdal.name`, `gw.bohdal.name`, reverse PTR checks for `10.1.30.53` and `10.1.100.1`, `www.bohdal.name`, `example.com`, a WAN/public endpoint check, and ICMP reachability to `8.8.8.8` as an external network reachability signal rather than DNS health.

Run v1 synthetic checks from inside the cluster only. Keep manual LAN smoke tests for DNS and defer a dedicated LAN probe location until the base observability stack is stable and path-specific client reachability checks are worth the extra host or agent lifecycle.

Include lightweight Kubernetes event collection in v1 if the VictoriaLogs or collector path supports it cleanly. Events should be searchable with general Kubernetes logs, use the same 7-day retention target, and avoid complex event correlation until a later design pass.

Rely on Kubernetes and node-level exporters for Talos node visibility in v1. Defer Talos API-specific metrics or log collection until a later pass identifies concrete gaps around OS upgrades, machine health, or host services, because Talos-specific collection adds credentials and another integration path.

Include kube-state-metrics and node exporter in v1 metrics collection. They are foundational for Kubernetes object state, pod and deployment health, PVC status, node CPU and memory, filesystem usage, and basic network visibility.

Start v1 Kubernetes metrics with easy and safe sources: kube-state-metrics, kubelet/cAdvisor where available, node exporter, and Cilium. Defer direct scraping of API server, controller-manager, scheduler, and etcd metrics unless Talos and Kubernetes expose those endpoints cleanly without weakening control-plane security.

NetFlow or sFlow collection is a desired future observability capability for network traffic analysis. Treat it as its own later design branch because it needs decisions about exporters, receiver placement, sampling, retention, storage/query model, device support, and privacy before it is added to the v1 stack.

Use SNMP and syslog before credentialed network-device API polling. Avoid UniFi API credentials in v1 unless there is a clear observability gap, store SNMP communities or SNMPv3 credentials through Bitwarden and Kubernetes secrets only, prefer SNMPv3 when practical, and restrict any SNMPv2c community by source IP and firewall policy.

For MikroTik metrics, prefer SNMPv3 in v1. Allow SNMPv2c temporarily only if the community string is secret-managed, access is restricted to observability scraper source addresses, MikroTik firewall policy blocks broad LAN access, and the temporary nature is documented.

Deploy v1 observability through Flux with a mixed model. Use Helm releases for large vendor components or operators when that materially improves lifecycle management, such as VictoriaMetrics Operator or Grafana, and use plain YAML for local wiring, scrape resources, alert rules, dashboards-as-config, exporters, NetworkPolicy, and small services where direct reviewability matters more.

Create `docs/observability-design.md` before adding observability manifests. The design document should consolidate the settled project-memory decisions into an implementation-oriented plan covering scope, non-goals, storage dependency, components, Flux ordering, DNS and VIP names, security posture, retention, and validation checklist.

Pin observability images by immutable digest for plain manifests. For Helm-managed components, pin Helm chart versions and app versions at minimum, and use image digest overrides where the chart supports them cleanly without brittle values; defer awkward chart-rendered digest pinning case by case instead of making the deployment unmaintainable.

Split observability into dependency-ordered Flux components rather than one large component. Keep cluster storage separate from observability: use a generic infrastructure component such as `storage-synology-csi` for the Synology CSI driver and cluster StorageClasses, then use `observability-foundation` for namespace and shared policy, `victoriametrics-operator` for the operator install, `observability-storage` for `VMSingle` and `VLSingle`, `observability-collection` for agents, exporters, scrape configs, and syslog receivers, `observability-ui` for Grafana datasources and dashboards, `observability-alerting` for VMAlert rules and alert visibility, and `observability-access` for Cloudflare Tunnel/Access integration when that follow-up starts. `observability-storage` depends on the generic cluster storage component being validated.

Apply generic cluster storage after `cluster-policy` and Cilium, independent of DNS. The `storage-synology-csi` Flux component should depend on `cluster-policy` and `cilium`; DNS and storage should not depend on each other, while observability storage depends on the generic storage component being validated.

Create `docs/storage-design.md` before implementing Synology CSI. Keep it focused on Synology CSI as generic cluster storage: purpose, Talos `siderolabs/iscsi-tools` requirement, StorageClass shape, credential handling, validation checklist, failover test, and explicit exclusions such as default StorageClass, NFS, and backup automation.

Use persistent volumes from day one for VictoriaMetrics, VictoriaLogs, and Grafana. Start with explicit but modest PVC sizing: 20-50 Gi for `VMSingle`, 20-50 Gi for `VLSingle`, and 2-5 Gi for Grafana; agents and exporters should stay ephemeral unless a specific component requires local state. The cluster does not have a committed StorageClass yet, so observability storage depends on choosing and deploying a stable StorageClass before the storage component can be considered complete.

Synology CSI is the leading candidate for the first generic NAS-backed cluster StorageClass because the storage backend is a Synology NAS. Prefer iSCSI-backed RWO volumes for stateful single-writer workloads such as VictoriaMetrics, VictoriaLogs, and Grafana if Talos compatibility is validated; reserve NFS for later RWX/shared-file use cases. Sidero documents a Talos-specific Synology CSI path that requires Synology DSM 7.0 or newer, Kubernetes v1.20 or newer, the `siderolabs/iscsi-tools` Talos extension, Synology API credentials with admin capability but no volume permissions, a Talos-compatible Synology CSI image, and a test PVC/performance job. The Talos image schematic now includes `siderolabs/iscsi-tools`, so rolling nodes onto that image and proving a live iSCSI PVC remain prerequisites before any dependent workload storage is treated as ready.

Make Synology CSI a generic cluster infrastructure task that must land before observability storage, not an observability-specific component. The storage task should roll or update Talos nodes onto the iSCSI-capable image, deploy the Talos-compatible Synology CSI driver, create an explicit-only non-default iSCSI StorageClass with `ext4`, `Retain` reclaim policy, `WaitForFirstConsumer` volume binding, and volume expansion enabled for RWO data volumes, and validate bind, mount, read/write, detach/reattach, pod rescheduling, cross-node failover, and expansion behavior before deploying VictoriaMetrics, VictoriaLogs, Grafana, or any other dependent workload with PVCs. Failover validation must include moving a test workload to another Talos node and confirming the iSCSI volume detaches, reattaches, and preserves data before the StorageClass is considered production-ready. Defer any `Delete` reclaim policy class until disposable storage workloads need it.

Use Bitwarden as the source of truth for Synology CSI DSM credentials. For the first live validation, it is acceptable to create the Kubernetes Secret manually from Bitwarden-sourced values as long as credentials are not committed, echoed, or exposed in logs; automate secret injection only after the CSI path itself is proven.

Validate Synology CSI snapshot capability if it is straightforward during storage bring-up, but do not make snapshot or backup automation part of v1. PVC persistence, cross-node failover, expansion, and retained-volume behavior are required first; automated backups can be designed later once the StorageClass is trusted.

Use one shared `observability-system` namespace for the v1 observability control plane, including Grafana, VictoriaMetrics, VictoriaLogs, collectors, exporters, and alerting components unless a component has a strong reason to live elsewhere. Scrape targets may remain in their source namespaces, such as DNS metrics services in `dns-system`.

Use restricted-by-default Pod Security Admission and pod security settings for observability where images support it. Prefer non-root execution, read-only root filesystems, RuntimeDefault seccomp, dropped capabilities, and no service account token unless a component needs Kubernetes API access; document any component-specific fallback to a weaker posture narrowly instead of inheriting DNS's baseline exception.

Use default-deny NetworkPolicy in `observability-system`, staged with component manifests so the stack does not deadlock. Explicitly allow only required paths: scrapers to targets, Grafana to VictoriaMetrics and VictoriaLogs, collectors to storage endpoints, syslog ingress from approved network-device subnets to the syslog VIP, blackbox egress to approved probe targets, DNS egress where needed, and Kubernetes API access only for components that need discovery or event collection.

Expose Grafana on the LAN first with a local Grafana login and a secret sourced from the repository's secret-management path. Plan to make Grafana available through Cloudflare Zero Trust soon after the LAN path works, using Cloudflare Access in front of a Cloudflare Tunnel route so the public hostname is policy-protected before it is published. The final Grafana naming model is `grafana.bohdal.name` as the canonical Cloudflare Access protected hostname for normal LAN and remote use, and `grafana.internal.bohdal.name` as the direct LAN break-glass hostname protected by Grafana login plus trusted-network controls.

Use `internal.bohdal.name` as the internal-only DNS namespace for direct LAN service names. Prefer explicit records such as `grafana.internal.bohdal.name` and `syslog.internal.bohdal.name`; do not add a wildcard record for `*.internal.bohdal.name` by default because explicit names are safer, more reviewable, and avoid hiding typos or undeployed services.

When the corresponding services exist, add explicit internal DNS records for observability service VIPs: `syslog.internal.bohdal.name A 10.1.30.54` and `grafana.internal.bohdal.name A 10.1.30.55`. Add matching PTR records `54.30.1.10.in-addr.arpa PTR syslog.internal.bohdal.name.` and `55.30.1.10.in-addr.arpa PTR grafana.internal.bohdal.name.` at the same time. Do not add these records before the service VIPs are allocated and reachable.

Use only `syslog.internal.bohdal.name` as the v1 syslog target name. Do not add a `log.internal.bohdal.name` alias because `log` is ambiguous across syslog, Kubernetes logs, VictoriaLogs, and future flow logs.

Use a stable internal Cilium LoadBalancer VIP for the Grafana break-glass path if it can be secured in the same change. Reserve `10.1.30.55` for `grafana.internal.bohdal.name` if it is free, restrict it to trusted management networks through router/firewall policy and Kubernetes NetworkPolicy where applicable, and keep Grafana login enabled.

Treat Git as the source of truth for Grafana datasources, dashboards, folders, and other supported provisioning. Grafana UI edits are acceptable for exploration, but durable dashboards and configuration should be committed back to Git; the Grafana PVC should hold runtime state rather than become the authoritative dashboard store.

Use a small curated dashboard set in v1 and commit every dashboard JSON that deployment depends on. Upstream or community dashboards may be used as references or imported starting points, but runtime provisioning should not depend on live dashboard IDs. The initial dashboard set should cover Kubernetes cluster health, node resources, Cilium/BGP networking, DNS through Blocky/CoreDNS plus synthetic checks, VictoriaMetrics/VictoriaLogs self-monitoring, MikroTik metrics, and syslog overview.

Do not introduce a general ingress controller only for v1 observability. Expose only Grafana, have Cloudflare Tunnel target Grafana's internal HTTP service or a minimal direct service path, and keep VictoriaMetrics, VictoriaLogs, exporters, and collector endpoints cluster-internal. Revisit a shared ingress controller only when multiple internal HTTP services need the same routing layer.

DNS observability should preserve client IPs because Blocky is intentionally exposed with `externalTrafficPolicy: Local`. Metrics and logs should keep that source-IP requirement visible when dashboards and alerts are designed.

DNS v1 observability should use Blocky/CoreDNS metrics and synthetic checks only. Keep DNS query log shipping disabled by default because query logs expose client behavior; revisit query logs later only with explicit retention, access-control, and privacy decisions.

Blocky already exposes an internal HTTP listener on port `4000` with Prometheus metrics enabled at `/metrics`. It is intentionally exposed only through a ClusterIP service and should not be published on the LAN DNS VIP.

CoreDNS has the `prometheus` plugin enabled on pod port `9153`, but no metrics Service exists yet. The initial design deliberately kept CoreDNS health, readiness, and metrics pod-local or cluster-internal until an observability stack defines scraping conventions.

Add an internal ClusterIP metrics Service for CoreDNS as part of observability work. Keep it cluster-internal and restrict access to the observability namespace or collector pods through NetworkPolicy; do not expose CoreDNS metrics on the LAN.

DNS query logs currently go to stdout only. Do not add long-term DNS query log shipping until retention, access control, and privacy expectations are explicit, because DNS logs expose client behavior.

Manual smoke tests remain the first validation layer: UDP and TCP `dig` against `10.1.30.53`, internal A records, reverse PTR records, public `www.bohdal.name`, and a neutral public domain such as `example.com`.

## Observability Options To Evaluate

Use VictoriaMetrics Operator as the Kubernetes-native metrics path. That path will likely add a metrics Service or VM scrape resource for Blocky and CoreDNS and keep scrape access constrained by namespace and NetworkPolicy.

Use Grafana Alloy, OpenTelemetry Collector, VictoriaLogs Agent, or another collector only if it materially simplifies collection. This may be useful if DNS stdout logs need selective parsing, redaction, sampling, or routing before storage.

Use VictoriaLogs for short-retention DNS application logs only after deciding retention and privacy policy. Prefer stable stream fields such as namespace, app, pod, node, device, facility, and severity; avoid turning query name, client IP, or full answer into primary routing dimensions unless the privacy and cardinality implications are explicit.

Use alerting rules that distinguish local DNS failure from public upstream failure. Pod readiness should stay local-chain only; public DNS4EU issues should be separate alerts based on synthetic checks or resolver metrics, not readiness gates.

Add synthetic DNS monitoring later from the observability stack rather than as a standalone CronJob. Useful checks include `dns.bohdal.name A`, `gw.bohdal.name A`, reverse PTRs for `10.1.30.53` and `10.1.100.1`, `www.bohdal.name A`, `example.com A`, and both UDP and TCP query paths. Do not assert exact public IPs for public names.

When observability is introduced, revisit NetworkPolicy for Blocky HTTP metrics and CoreDNS metrics. The current first implementation allows Blocky HTTP inside the cluster and has no CoreDNS metrics Service; future policy should restrict scraping to the observability namespace or collector pods.

Keep DNS4EU filtering validation deferred unless DNS4EU documents a stable test domain for the Protective + Ad Blocking profile.
