# Observability design

This document is the implementation contract for Home Infrastructure Observability in the `sk-talos` cluster. It records the decisions agreed before manifests are introduced.

## Goals

Run one Kubernetes-hosted platform that collects and correlates metrics, Kubernetes and Talos logs, network syslog, SNMP data, Kubernetes audit events, and synthetic checks for the active home infrastructure.

The platform should remain simple enough for a home lab, preserve one year of raw metrics, retain logs for 30 days, provide useful dashboards, and send low-noise actionable alerts.

## Non-goals

The first release excludes distributed traces, NetFlow or sFlow, the legacy Kubernetes cluster, UniFi controller API polling, Klipper or Moonraker monitoring, raw telemetry backups, automated Bitwarden-to-Kubernetes secret reconciliation, and an external dead-man monitor.

Temporary observability downtime during a Kubernetes node, worker, or Synology outage is acceptable. The first release does not provide high availability for storage or Grafana.

## Architecture

Deploy the official `victoria-metrics-k8s-stack` Helm chart through a Flux `HelmRelease`. Use its VictoriaMetrics Operator, `VMSingle`, `VMAgent`, `VMAlert`, Alertmanager, kube-state-metrics, node exporter, scrape resources, and starter dashboards.

Deploy VictoriaLogs Single separately for logs. Run Vector as a DaemonSet and use it as the single collector for Kubernetes container logs, network syslog, Talos service logs, Talos kernel logs, and Kubernetes audit events.

Use Grafana as the only user-facing observability service. Provision VictoriaMetrics and VictoriaLogs data sources, including a pinned `victoriametrics-logs-datasource` plugin. Keep VictoriaMetrics, VictoriaLogs, Alertmanager, exporters, and ingestion APIs on `ClusterIP` services.

Use Blackbox Exporter for synthetic checks and Prometheus SNMP Exporter for network and hardware polling. Use a dedicated read-only Proxmox exporter identity with the `PVEAuditor` role.

Use single replicas for VictoriaMetrics, VictoriaLogs, Grafana, Alertmanager, and other stateful control-plane components. Vector remains a DaemonSet. Run two replicas of the reusable Cloudflare Tunnel connector.

Use `cluster="sk-talos"` and `site="sk"` as stable global identity labels.

## Dependencies

The existing `synology-iscsi-retain` StorageClass must pass provisioning, persistence, cross-node reattachment, expansion, and retained-volume validation before any observability PVC is deployed.

Add one general-purpose Talos worker with 4 vCPU and 8 GiB RAM before the full stack is installed. Keep ordinary workloads off the control-plane nodes through the existing control-plane taints; the observability workloads do not require a dedicated worker label or taint.

Enable Cilium agent and operator metrics plus a low-cardinality Hubble metric set for DNS, drops, and TCP. Do not enable Hubble UI or broad per-flow labels.

Add an internal CoreDNS metrics Service and retain Blocky's existing cluster-internal metrics Service. Monitor Flux controllers and reconciliation state.

## Flux and infrastructure ownership

Use Flux for in-cluster components and configuration. Use Helm releases for vendor stacks and plain manifests for local wiring, inventory, scrape resources, alert rules, dashboards, services, and policies.

Manage Cloudflare DNS, Tunnel, Access application, and Access policy with a separate OpenTofu stack. Manage the reusable `cloudflared` deployment with Flux in a dedicated infrastructure namespace. The tunnel is shared infrastructure; Grafana is its first explicit route rather than its owner.

Use a dependency-ordered rollout:

1. Add the general-purpose Talos worker.
2. Validate Synology CSI storage as a hard gate.
3. Add cert-manager and the reusable Cloudflare Tunnel infrastructure.
4. Deploy the metrics stack and Grafana.
5. Deploy VictoriaLogs, Vector, syslog, Talos log forwarding, and audit logging.
6. Add SNMP, Proxmox, and blackbox targets.
7. Add reviewed dashboards, alerts, and notification routing.

Proceed between stages after automated validation and workload smoke tests pass. A fixed soak period is not required, but stop progression on dropped data, repeated restarts, capacity pressure, or excessive alert noise.

Pin exact Helm chart, application, container, and Grafana plugin versions. Review upgrades manually in separate pull requests; do not use floating tags or unattended upgrades.

## Storage and retention

Use retained Synology iSCSI PVCs with these initial capacities:

- VictoriaMetrics: 100 GiB
- VictoriaLogs: 50 GiB
- Grafana: 10 GiB
- Alertmanager: a small retained volume sized for silences and notification state

Retain raw metrics for one year. VictoriaMetrics OSS does not provide age-based tiered downsampling, so do not add recording-rule aggregates merely to simulate it. Measure actual ingestion for the first month and reassess annual capacity before adding another storage tier or changing editions.

Retain all collected logs, including DNS query logs and audit logs, for 30 days. Enforce the retention period with bounded PVC capacity and alerts at 70% and 85% usage.

Do not back up raw telemetry in the first release. Reconstruct dashboards, data sources, rules, scrape definitions, and collectors from Git; reconstruct secrets from Bitwarden. Preserve PVCs during rollback and require a separate explicit decision before deleting retained PVs or Synology LUNs.

Use Grafana's SQLite database on its retained PVC. This is sufficient for one replica and one user because durable dashboards and configuration remain Git-managed.

## Metrics collection

Use these default scrape intervals:

- Kubernetes and general exporters: 30 seconds
- Network SNMP: 60 seconds
- APC UPS: 30 seconds
- Blackbox probes: 30 seconds

Apply generous per-job sample and label limits. Raise limits only for reviewed exporters so a broken endpoint cannot consume the one-year storage budget.

Collect Kubernetes object state, node metrics, kubelet and cAdvisor metrics where securely available, API server metrics, etcd metrics where securely available, Cilium and limited Hubble metrics, Flux controller metrics, Blocky metrics, CoreDNS metrics, and observability self-metrics.

Do not broaden scheduler, controller-manager, or other Talos control-plane listeners solely to fill dashboard gaps. Security takes priority over exhaustive control-plane coverage.

Commit an explicit external target inventory containing stable device name, management address, exporter type, SNMP module, interval, and availability class. Do not scan subnets for targets.

## SNMP and device integrations

Support SNMPv2c and SNMPv3. Prefer SNMPv3 `authPriv`; use v2c for incompatible devices. Store all community strings, usernames, and authentication and privacy keys in Bitwarden-backed Kubernetes Secrets.

Start with standard system and interface objects plus vendor-specific modules for MikroTik, UniFi access points, Synology, APC UPS, and a Brother printer. Perform narrow read-only discovery of `sysName.0`, `sysDescr.0`, and `sysObjectID.0` from a user-confirmed seed list before selecting vendor modules.

Commit the SNMP generator input and generated `snmp.yml`. Do not commit vendor MIB files unless their redistribution licenses permit it; document their sources and versions.

Use SNMP only for MikroTik and Synology initially. Defer RouterOS and DSM API exporters until a concrete SNMP gap exists.

Monitor UniFi access points through SNMP. Add UniFi Poller only after the UniFi controller is migrated from the legacy cluster.

Use a dedicated Proxmox API token with the read-only `PVEAuditor` role at `/`; never reuse the OpenTofu provisioning identity.

The Brother printer and Klipper printer are intermittent devices and must not alert merely because they are powered off. Klipper and Moonraker monitoring is otherwise fully deferred because Moonraker lacks a confirmed endpoint-scoped read-only credential.

Device-side polling ACLs may allow the whole relevant VLAN. This is an accepted home-lab risk even though four explicit Talos node addresses would provide a narrower boundary.

## Synthetic checks

Run Blackbox Exporter inside `sk-talos` and probe:

- MikroTik gateway and internet reachability with ICMP
- Blocky through a real DNS query
- Grafana through HTTPS
- One stable external HTTPS endpoint

Do not monitor Moonraker in the first release. Keep path-specific probes from outside Kubernetes and an external dead-man heartbeat as tracked follow-ups.

## Logs and syslog

Run Vector as a DaemonSet in the shared observability namespace. Collect pod logs by default, support an explicit pod annotation for exclusion, and avoid ingesting Vector output in a way that creates loops.

Expose network syslog through a fixed Cilium LoadBalancer IP on UDP/514 and TCP/514. Prefer TCP when a device supports it; retain UDP for compatibility. Do not expose syslog through Cloudflare or the public internet.

Expose Talos structured log ingestion on a separate TCP port at the same logging VIP. Configure Talos 1.13 service and kernel log forwarding in JSON-lines format. Parse this stream separately from RFC syslog.

Preserve the original sender address through the LoadBalancer and store it as a normalized field. Original source-IP preservation is a hard requirement.

Preserve raw message, sender, receive timestamp, transport, and parse status when syslog parsing fails. Store both sender timestamps and Vector receipt timestamps. Use the sender timestamp only when it is valid and within an allowed clock-skew window.

Use a bounded 1 GiB Vector disk buffer per node. TCP senders may receive backpressure when the buffer fills; UDP messages may be lost. Apply generous per-source flood limits, expose dropped-event counters, and alert when dropping begins.

Collect Kubernetes API audit events with a security-focused metadata policy covering authentication and authorization failures, RBAC changes, secret access, and workload mutations. Exclude request and response bodies so credentials and secret values cannot enter VictoriaLogs. The implementation must verify Talos 1.13's supported audit delivery path before changing machine configuration.

Collect Blocky DNS query logs with full client IP and queried domain for 30 days. Store those values as ordinary log fields, not stream fields; restrict access to Grafana's sole user and never include query details in alert notifications.

Keep stable log stream fields limited to values such as cluster, site, source type, namespace, workload, pod, container, node, device, facility, and severity. Do not promote messages, URLs, request IDs, filenames, DNS names, client addresses, MAC addresses, or print-job names into stream fields.

## Grafana and access

Grafana is the only LAN-facing and Cloudflare-published observability service. Disable anonymous access and require Grafana's own login on both paths. Store the administrator credential in Bitwarden.

Only one user is expected. Use a single Grafana organization and do not add multi-tenancy.

Use `grafana.bohdal.name` as the canonical name. Internal split DNS resolves it to a fixed Cilium LoadBalancer VIP; public DNS routes it through the shared Cloudflare Tunnel. Allow direct Grafana ingress from `10.0.0.0/8`, an intentionally broad home-lab trust boundary.

Install cert-manager and issue a browser-trusted certificate through ACME DNS-01 using a narrowly scoped Cloudflare token. Grafana serves HTTPS directly, so do not add an ingress controller solely for observability.

Configure Cloudflare Access with Google as the identity provider, allow only the exact approved Gmail account, require Google MFA, and deny all other identities. Cloudflare Access is an additional perimeter and does not replace Grafana authentication.

Keep data sources, folders, dashboards, alert-related data sources, and supported provisioning in Git. UI experiments may live in a scratch folder but must be exported to Git before they become operational dependencies.

Provision official VictoriaMetrics and Kubernetes dashboards, then add focused dashboards for network, APC UPS, Synology, Proxmox, DNS, ingestion health, Cilium/BGP, and syslog. Review and pin community dashboards before committing them; do not depend on runtime downloads by dashboard ID.

## Alerting

Use VMAlert and `VMRule` resources for metric and synthetic-probe alerts. Defer log-derived alerts until a specific event cannot be represented reliably as a metric.

Send only sustained, actionable alerts. Classify targets as always-on or intermittent and suppress offline notifications for the Brother and Klipper printers.

Initial alerts cover device or node unreachability, Kubernetes node readiness, repeated pod crashes, PVC capacity, sustained resource pressure, VictoriaMetrics and VictoriaLogs ingestion failures, Vector drops or buffer pressure, scrape failures, VMAlert evaluation failures, Alertmanager delivery errors, interface down or sustained errors, UPS on-battery and low-runtime states, DNS and HTTP probe failures, Flux reconciliation failures, Grafana availability, and expiring TLS certificates.

Route severities as follows:

- `critical`: Telegram and Discord
- `warning`: Discord only
- `info`: visible in Alertmanager and Grafana without push delivery unless explicitly opted in

Use a dedicated private Telegram group and bot. Use a Discord webhook for the lower-priority stream. Store both credentials in Bitwarden and use bounded grouping, recovery notifications, and dependency-based inhibition.

Configure inhibition so node failures suppress dependent pod and scrape alerts, device failures suppress interface symptoms, and backend failures suppress downstream ingestion noise. Add Alertmanager to Grafana so planned maintenance uses time-bounded silences rather than alert-rule edits.

## Security

Use one shared observability namespace for Vector, Grafana, VictoriaMetrics, VictoriaLogs, exporters, and alerting. Vector's host log mounts weaken namespace-level Pod Security isolation for the other workloads; this is an explicitly accepted tradeoff. Still grant Vector only its required mounts and capabilities and apply hardened security contexts to every component where supported.

Apply namespace-wide resource requests, practical memory limits, and an aggregate quota that leaves worker headroom for eviction and recovery.

Use default-deny policies and explicitly allow required component flows. Use Cilium DNS-aware `toFQDNs` egress policy plus DNS proxy rules for Telegram, Discord, Cloudflare, ACME, and the pinned Grafana plugin source rather than broad outbound HTTPS.

Keep VictoriaMetrics and VictoriaLogs unauthenticated inside the cluster. Their ClusterIP services remain accessible only to explicitly authorized pods through NetworkPolicy. Revisit `vmauth` if external writers or multiple tenants are introduced.

Bitwarden Secrets Manager remains the source of truth. For the first release, use a documented non-logging bootstrap procedure to create narrowly scoped Kubernetes Secrets manually. Do not introduce External Secrets Operator and its Bitwarden SDK server or read-write machine token yet.

Collect all Kubernetes namespaces by default, with explicit exclusions. Drop known sensitive structured fields before storage, but treat any secret emitted in application log text as a source defect that must be fixed at the producer.

## Network addresses

Use fixed Cilium LoadBalancer IPs for Grafana and the combined syslog/Talos logging endpoint. Select addresses only after checking live Cilium and MikroTik state; do not rely on the previously proposed unverified reservations.

Commit the selected non-secret addresses and matching internal A/PTR records only after the services are reachable. Preserve source IPs on the logging endpoint.

## Validation and rollback

Every deployment PR must define and pass checks appropriate to its manifests. Render Helm and Kustomize output, validate schemas and custom resources, lint YAML and Markdown, scan rendered output for secrets, and use server-side dry-run where installed CRDs are required.

Workload acceptance must verify PVC attachment and persistence, Grafana HTTPS and both data sources, the pinned VictoriaLogs plugin, expected scrape targets, one-year and 30-day retention settings, Vector parsing and sender identity, TCP and UDP syslog, Talos service and kernel logs, audit-event delivery without bodies, SNMPv2c and SNMPv3 discovery, synthetic probes, DNS query privacy fields, default-deny policy flows, capacity alerts, and observability self-metrics.

Trigger dedicated synthetic alert rules to verify Telegram and Discord routing, grouping, inhibition, recovery messages, and secret masking. Do not break production services for alert tests; remove or disable the test rules after acceptance.

Rollback by reverting or suspending Flux resources while retaining PVCs. Never delete retained PVs or Synology LUNs as part of routine rollback.

## Follow-up debt

Track these items explicitly after the first release:

- Raw telemetry backup or snapshot strategy
- External dead-man heartbeat outside the Kubernetes and home internet failure domains
- Automated Bitwarden secret reconciliation after its SDK-server and token risks are revisited
- UniFi Poller after the controller migration
- Klipper and Moonraker monitoring after exporter and read-only authentication review
- NetFlow or sFlow design
- Distributed tracing after applications emit OpenTelemetry spans
- Pre-bundled Grafana image if runtime plugin installation becomes unreliable
- Additional workers or clustered VictoriaMetrics-family storage if availability requirements change
- Path-specific synthetic probes from a LAN host outside Kubernetes
