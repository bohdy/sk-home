# Observability rollout

This document is the resumable execution checkpoint for the observability implementation defined by `docs/observability-design.md`. Update it after each merged deployment stage so a later session can continue from repository and cluster facts instead of conversation history.

## Current checkpoint

The cluster foundations are deployed and healthy:

- Talos node names are deterministic, and one general-purpose 4 vCPU/8 GiB worker is available.
- Flux v2.8.8 reconciles the cluster from `main`.
- Cilium, cert-manager v1.20.1, the production Let's Encrypt `ClusterIssuer`, and Synology CSI are Ready.
- The `synology-iscsi-retain` StorageClass passed provisioning, persistence, cross-node reattachment, expansion, and retained-volume validation.
- The shared Cloudflare Tunnel has two `cloudflared` 2026.7.2 replicas and a catch-all 404 route. Grafana is not routed through it yet.
- The retained storage validation PV remains intentionally preserved for later manual cleanup.

The metrics stage is deployed and accepted. PRs #85, #86, and #87 introduced the stack, added the namespace-scoped Pod Security exception required by node exporter, and preserved Grafana's Helm-managed PVC during remediation.

The in-cluster `observability` namespace and `grafana-admin` Secret have already been bootstrapped. Bitwarden Secrets Manager item `SK-TALOS-GRAFANA-ADMIN-PASSWORD` stores only the Grafana administrator password; the Kubernetes Secret uses the `admin-user` and `admin-password` keys. Never print the secret value or commit rendered Secret data.

## Metrics acceptance

Acceptance completed on 2026-07-17:

- Flux `observability-metrics` and Helm release revision 2 reported Ready at Git revision `81d6ca6`.
- VMSingle, VMAgent, VMAlert, Alertmanager, Grafana, kube-state-metrics, and four node exporters were Ready with zero restarts.
- VMAgent reported 32 active targets, no unhealthy targets, and 480 intentionally dropped discovery targets.
- VMSingle returned 32 `up` series, all with `cluster="sk-talos"` and `site="sk"`, while ingesting approximately 5,800 rows per second during acceptance.
- The live VMSingle specification reported `retentionPeriod: 1y`, `scrapeInterval: 30s`, and a retained 100 GiB claim.
- Grafana 13.1.0 reported a healthy database and successfully queried its default VictoriaMetrics data source.
- A temporary Grafana dashboard survived pod deletion and rollout on the retained claim, then was removed.
- The worker reported no memory, disk, PID, or network pressure with 39% requested CPU and 35% requested memory after deployment.
- Active retained PVs are `pvc-a1b722da-92ef-4772-b66a-6d89b3b2ce37` for VMSingle, `pvc-3e14274e-2c25-4005-a08e-ef1796fa310b` for Grafana, and `pvc-fe9fd1e9-2fc9-4555-a843-af46e1d73625` for Alertmanager.
- Released PV `pvc-ac677c3b-8897-43e8-a538-dd34d71a3baf` is the first failed-install Grafana volume. It remains intentionally retained alongside storage-validation PV `pvc-c18327d7-51df-451f-80ac-daac0c4bb6dc`; remove either only through explicit storage cleanup.

## Immediate next actions

1. Add SNMP Exporter with a committed target inventory and reviewed vendor-specific modules for MikroTik, UniFi APs, Synology, APC UPS, and Brother printers.
2. Bootstrap the required SNMPv2c and SNMPv3 credentials from dedicated Bitwarden Secrets Manager items without committing or logging their values.
3. Verify every configured device, intermittent-printer behavior, collector health, stable target labels, and resource use before proceeding to the Proxmox and Blackbox exporters.

## Vector acceptance

Acceptance completed on 2026-07-17:

- Flux `observability-vector` and Vector Helm release revision 2 reported Ready on chart and application version 0.57.0.
- Four Agent DaemonSet pods covered all three control-plane nodes and the worker with zero restarts.
- VictoriaLogs contained normalized Kubernetes records from every node and no records from Vector's own pods.
- Four Vector internal-metrics targets reported `up=1` with stable `cluster="sk-talos"` and `site="sk"` labels.
- No component-error or discarded-event rate was present during acceptance.
- A continuous ordinary test pod produced exactly 60 records, while an otherwise identical pod annotated `vector.dev/exclude: "true"` produced zero.
- Recreating the worker's Vector pod while the test emitter ran preserved its node-local checkpoint: the stream finished at exactly 60 records without replay, and the replacement collector became Ready with zero restarts.

## Syslog acceptance

Acceptance completed on 2026-07-20. PRs #94, #96, and #97 introduced syslog ingestion, per-sender throttling, and the required Helm template escaping:

- The `syslog` Cilium LoadBalancer requests fixed VIP `10.1.30.54`, accepts TCP and UDP on port 514 from `10.0.0.0/8`, and uses `externalTrafficPolicy: Local` to preserve the original sender address.
- Every Vector Agent listens for newline-delimited TCP syslog and UDP syslog. TCP records are limited to 262,144 bytes and UDP datagrams to 65,507 bytes.
- Parsing is fallible by design. Every record retains `raw_message`, `transport`, and parse status; malformed input is retained with its parse error instead of being silently discarded.
- Normalized records use receipt time for the VictoriaLogs storage timestamp while retaining the sender timestamp separately. They include stable `cluster`, `site`, `source_type`, sender, and device fields.
- Valid and malformed TCP and UDP records sent first from WireGuard address `10.1.250.10` and then from LAN address `10.1.10.10` remained queryable with the original sender, correct transport and parse status, retained raw input, receipt and sender timestamps, `cluster="sk-talos"`, and `site="sk"`.
- All four marked validation records survived VictoriaLogs pod recreation. All four Vector scrape targets remained `up=1`, buffers drained, and the collectors reported no recent component errors or restarts.
- A 2,501-record TCP flood produced 1,128 stored events and 1,373 throttled events. A paced 1,800-record UDP flood delivered 1,796 events to Vector, stored 1,671, and throttled 125. Ordinary records continued to pass.
- Vector 0.57.0 does not expose `component_discarded_events_total` for throttle drops even with per-key discarded metrics disabled. Alerting must derive aggregate throttle drops from the difference between the throttle component's received and sent event counters; sender labels remain intentionally absent to prevent attacker-controlled cardinality.

## Talos log acceptance

Acceptance completed on 2026-07-20. PRs #96, #98, and #99 introduced Talos forwarding, corrected kernel identity, and replaced the shared-VIP path with direct node-local delivery:

- Talos service and kernel logging is applied to all three control planes and the worker. Each node has a runtime `KmsgLogConfig`, and service logs carry the committed node name as an extra tag.
- Talos kernel records have no node tag. Each node therefore connects to TCP hostPort 6051 on its own management address, bypassing Kubernetes Service load balancing; Vector assigns the receiving Agent's Downward API node name as the stable device identity.
- Live socket inspection showed two established streams per node, with every connection terminating at the Vector pod on that same node.
- VictoriaLogs contained parsed service and kernel records for `sk-talos-cp-1`, `sk-talos-cp-2`, `sk-talos-cp-3`, and `sk-talos-worker-1`. Records retained sender and receipt timestamps, correct stream classification, and stable `cluster="sk-talos"` and `site="sk"` fields.
- Flux applied Git revision `07eb8a8`, Vector Helm revision 6 became Ready, and four Agent pods ran with zero restarts. The main OpenTofu workflow run `29728168676` applied the endpoint changes successfully.
- The final Talos health check passed etcd, API, kubelet, boot-sequence, static-pod, component-readiness, and schedulability checks. Kubernetes node creation timestamps remained unchanged from 2026-07-17, confirming that configuration reconciliation did not reboot a node.

## Kubernetes audit acceptance

Acceptance completed on 2026-07-20. PRs #101 and #102 introduced metadata-only Kubernetes API auditing and preserved authenticated and impersonated identities separately:

- Talos applies an explicit kube-apiserver audit policy to all three control-plane nodes. It omits the `RequestReceived` stage and records metadata without request or response bodies.
- Vector mounts only `/var/log/audit/kube` read-only with `DAC_READ_SEARCH`, follows the active `kube-apiserver.log`, and excludes the existing rotated archives from initial discovery.
- Five embedded Vector tests cover normalized events, missing optional fields, malformed payload handling, explicit removal of request and response objects, and impersonated identity.
- VictoriaLogs contained parsed audit records from every control-plane node. Temporary ConfigMap and Role create/delete operations, an authorized Secret read, an impersonated authorization denial, and an invalid-token authentication failure were all observed.
- Queries for `requestObject` and `responseObject` returned zero records. Malformed audit input omits its original text because content that cannot be parsed cannot be scrubbed safely.
- The live impersonation denial retained `username="admin"` as the authenticated caller and `impersonated_username="system:serviceaccount:observability:default"` as the effective authorization subject.
- OpenTofu workflow run `29733869644` applied the Talos audit configuration successfully. Flux applied Vector Helm revisions 8 and 9, and the final Agent rollout completed across all four nodes with zero repeated restarts.
- Concurrent kube-apiserver refresh briefly caused in-cluster API connection refusals and restarts of kube-state-metrics and the VictoriaMetrics operator. Both recovered after API availability returned, and the final cluster and observability workloads were healthy.

## Blackbox acceptance

Acceptance completed on 2026-07-20. PRs #106 and #107 introduced the exporter and corrected DNS egress after observing Cilium's in-cluster LoadBalancer translation:

- Flux `observability-blackbox` applied Git revision `2a41358` and reported Ready. Blackbox Exporter 0.28.0 ran on the general-purpose worker from its pinned multi-architecture digest with zero restarts.
- VMSingle reported `up=1` for the exporter self-scrape and both probe scrape jobs with stable `cluster="sk-talos"` and `site="sk"` labels.
- The MikroTik gateway IPv4 ICMP probe reported `probe_success=1` for logical instance `mikrotik-gw`.
- The Blocky DNS probe queried `gw.bohdal.name` through client-facing VIP `10.1.30.53`, required the expected `10.1.100.1` answer, and reported `probe_success=1` for logical instance `blocky`.
- The first DNS attempts timed out because Cilium translated the VIP to Blocky pod port 1053 before egress enforcement. The accepted policy retains the VIP rule and permits only Blocky pods in `dns-system` on UDP/TCP 1053.
- Recent exporter logs contained no errors after the policy correction. Current probe-duration samples were below one millisecond, and exporter self-metrics reported approximately 28.3 MiB resident memory.
- The Kubernetes Metrics API was unavailable during acceptance, so resource evidence came from the exporter's VMSingle process metrics rather than `kubectl top`.

## VictoriaLogs acceptance

Acceptance completed on 2026-07-17:

- Flux `observability-logs` and the VictoriaLogs Helm release reported Ready on chart 0.13.9 with VictoriaLogs v1.52.0.
- The live StatefulSet used `--retentionPeriod=30d` and `--retention.maxDiskUsagePercent=85`.
- Retained 50 GiB PV `pvc-55399cea-d465-4439-8517-423dca5704aa` was Bound through `synology-iscsi-retain`.
- A synthetic JSON-stream record was ingested with stable `cluster`, `site`, and `source_type` fields and remained queryable after VictoriaLogs pod recreation.
- VictoriaLogs self-monitoring reported `up=1` in VMSingle with `cluster="sk-talos"` and `site="sk"`.
- Grafana loaded signed plugin `victoriametrics-logs-datasource` version 0.29.0, its real-query health check returned OK, and its data-source query API returned the persisted acceptance record.
- VictoriaLogs and Grafana remained Ready with zero restarts after acceptance.

## Remaining stages

Continue with a fresh branch from current `main` for each coherent stage:

1. Add SNMP Exporter, committed target inventory, and reviewed SNMPv2c/SNMPv3 modules for MikroTik, UniFi APs, Synology, APC UPS, and Brother printer; treat the printer as intermittent.
2. Add the read-only Proxmox exporter, then add Grafana HTTPS and one explicitly selected stable external HTTPS target to Blackbox Exporter.
3. Add focused dashboards, actionable alert rules, inhibition, derived Vector throttle-drop alerting, Telegram delivery for critical alerts, Discord delivery for critical and warning alerts, and no push delivery for info alerts.
4. Publish only Grafana through a fixed LAN VIP, browser-trusted TLS, split DNS, the shared Cloudflare Tunnel, and Cloudflare Access restricted to the approved Gmail identity with MFA.
5. Run the complete acceptance suite from `docs/observability-design.md`, then update this checkpoint with measured ingestion, resource use, and any deferred debt.

Do not combine later stages merely to reduce pull-request count. Stop progression on dropped data, repeated restarts, storage or worker pressure, unexpected public exposure, secret leakage, or excessive alert noise.

## Secret inventory

Bitwarden Secrets Manager remains the source of truth. Kubernetes Secrets are manually bootstrapped with shell tracing disabled and values passed directly from `bws` without echoing or writing them to the repository.

Known item names needed by the rollout are:

- `SK-TALOS-GRAFANA-ADMIN-PASSWORD`: Grafana administrator password only
- `SK-TALOS-CLOUDFLARED-TOKEN`: shared Cloudflare Tunnel connector token only
- `CLOUDFLARE_API_TOKEN`: narrowly scoped DNS-01 token only
- `SK-TALOS-SYNO-CSI`: Synology CSI DSM password only

Create dedicated Bitwarden items before the stages that require SNMPv2c, SNMPv3, Proxmox, Telegram, or Discord credentials. Document each item's value contract next to its bootstrap procedure; never store a whole configuration block when the documented contract calls for a single credential.

## Deferred debt

Keep the design document's follow-up list authoritative. In particular, traces, Moonraker/Klipper monitoring, UniFi Poller, automated Bitwarden reconciliation, raw telemetry backup, NetFlow or sFlow, and an external dead-man monitor remain deferred.
