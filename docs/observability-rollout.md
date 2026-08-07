# Observability rollout

This document is the resumable execution checkpoint for the observability implementation defined by `docs/observability-design.md`. Update it after each merged deployment stage so a later session can continue from repository and cluster facts instead of conversation history.

## Current checkpoint

The cluster foundations are deployed and healthy:

- Talos node names are deterministic, and one general-purpose 4 vCPU/8 GiB worker is available.
- Flux v2.8.8 reconciles the cluster from `main`.
- Cilium, cert-manager v1.20.1, the production Let's Encrypt `ClusterIssuer`, and Synology CSI are Ready.
- The `synology-iscsi-retain` StorageClass passed provisioning, persistence, cross-node reattachment, expansion, and retained-volume validation.
- The shared Cloudflare Tunnel has two Ready `cloudflared` 2026.7.2 replicas, routes only public Grafana traffic to the in-cluster HTTPS Service, and retains a catch-all 404 route.
- Cilium agent, Cilium operator, low-cardinality Hubble DNS/drop/TCP, and Blocky telemetry are collected through a dependency-ordered Flux component. The pinned Cilium release runs the merged metric settings as Helm revision 2.
- Eight focused, repository-owned Grafana dashboards cover network interfaces, APC UPS, Synology, Proxmox, DNS, ingestion health, Cilium/BGP, and syslog without runtime dashboard downloads. Grafana has provisioned all eight; Proxmox panels now receive live data, while the remaining device-specific SNMP panels stay empty until their collectors are enabled.
- The retained storage validation PV remains intentionally preserved for later manual cleanup.

The metrics stage is deployed and accepted. PRs #85, #86, and #87 introduced the stack, added the namespace-scoped Pod Security exception required by node exporter, and preserved Grafana's Helm-managed PVC during remediation.

The in-cluster `observability` namespace and `grafana-admin` Secret have already been bootstrapped. Bitwarden Secrets Manager item `SK-TALOS-GRAFANA-ADMIN-PASSWORD` stores only the Grafana administrator password; the Kubernetes Secret uses the `admin-user` and `admin-password` keys. Never print the secret value or commit rendered Secret data.

## Resource guardrail acceptance

Acceptance completed on 2026-07-21 after PR #128:

- Flux `observability-base` applied exact revision `cc6b3e9`, and every observability Kustomization subsequently reported Ready at that revision.
- The live `observability-capacity` quota reported 1.705 of 4 requested CPU cores, 3,243 MiB of 6 GiB requested memory, 8.8 of 16 limited CPU cores, 11,520 MiB of 20 GiB limited memory, 17 of 30 active pods, 4 of 8 claims, and 161 of 300 GiB requested storage.
- A server-side dry-run pod without resource declarations received the exact LimitRange defaults: 25 millicores and 32 MiB requested, with 250 millicores and 256 MiB limited. No test pod was persisted.
- Kube-state-metrics exposed matching hard and used quota samples through VictoriaMetrics. `KubeCPUQuotaOvercommit`, `KubeMemoryQuotaOvercommit`, `KubeQuotaAlmostFull`, `KubeQuotaFullyUsed`, and `KubeQuotaExceeded` were loaded with evaluation health `ok` and remained inactive.
- Applying the admission controls did not initiate a workload rollout. Every active workload pod remained Running, and the namespace had no Warning events during acceptance.

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
- On 2026-08-02, node exporter CPU limits increased from 150m to 500m after healthy nodes showed sustained 28-51% throttling. The replacement pods reported 0-17.4% after the rollout, and every `CPUThrottlingHigh` alert cleared once retired cgroup series expired.

## Immediate next actions

1. Resolve the pinned RouterOS provider's RouterOS 7.21/7.22 incompatibility before retrying the manually gated gateway apply. Upstream issues `terraform-routeros/terraform-provider-routeros#944` and `#959` track the rejected `vrf` and `add-path-out` fields; proposed fix PR `#910` remains unmerged. Do not bypass OpenTofu state with an imperative REST creation merely to add the worker peer.

## Final release acceptance

Acceptance completed on 2026-08-02 after PR #195 deferred Brother printer SNMP acceptance until its administrator password can be reset:

- Flux fetched and every observability, DNS, and certificate Kustomization reported Ready at `main@sha1:be97d610991fd3302d496d01c589b385eabf05cd`. All Kubernetes nodes were Ready, every observability workload was Running or intentionally completed, and all four retained observability claims were Bound.
- VMagent had 66 active targets with no unhealthy target. The six SNMP-related scrapes covered the exporter, MikroTik, Synology, and all three UniFi APs; the five Blackbox-related scrapes covered the exporter plus Blocky DNS, external HTTPS, gateway ICMP, and Grafana HTTPS. Brother remains absent by design until the deferred device-side work is complete.
- VictoriaMetrics ingested approximately 6,162 rows per second with no remote-write packet drops. Its 100 GiB claim retained metrics for `1y`; VictoriaLogs returned healthy, retained logs for `30d`, and had ingested more than 41 million JSON-line records.
- cAdvisor series in VictoriaMetrics measured approximately 4.69 GB of observability working-set memory and 0.534 CPU cores over five minutes. The Kubernetes Metrics API remained unavailable, so `kubectl top` was not used for this evidence.
- Grafana 13.1.0 reported database `ok`; its certificate was Ready and valid until 2026-10-18. VMAlert execution errors, Alertmanager notification failures, and Vector component-error and discarded-event counters did not increase during the final one-hour window.
- Alertmanager had only the expected active `Watchdog` alert. Earlier Telegram and Discord synthetic-routing acceptance remains authoritative; no new notification was sent during this read-only final check.

## Network metrics acceptance

Acceptance completed on 2026-07-21 after PR #120 and the explicit Cilium Helm upgrade:

- Cilium 1.19.4 upgraded successfully to Helm revision 2. All four agents and the singleton operator rolled out with zero restarts, and every Kubernetes node remained Ready.
- Flux `observability-network-metrics` applied the merged component and reported Ready. Its two `VMPodScrape` and two `VMServiceScrape` resources reported operational.
- VMAgent discovered four healthy Cilium agent endpoints on port 9962, one healthy operator endpoint on port 9963, four healthy Hubble endpoints on port 9965, and both healthy Blocky endpoints on port 4000.
- VMSingle returned `up=1` for every new target with stable `cluster="sk-talos"` and `site="sk"` labels. The active series counts measured during acceptance were approximately 6,071 for Cilium agents, 540 for the operator, 1,097 for Hubble, and 213 for Blocky.
- Hubble is configured with exactly `dns drop tcp` and no context labels. Emitted drop series contain only protocol, reason, and service dimensions; TCP series contain only family, flag, and service dimensions. No pod, workload, identity, IP, or DNS-name context labels were present.
- Direct Hubble endpoint inspection exposed drop and TCP counters. DNS metric names remained absent after a temporary ordinary pod lookup, so DNS L7 event emission is not yet proven even though the `dns` handler is enabled; do not add query labels or DNS visibility policy without a separate cardinality and enforcement review.
- Blocky exported query, response, cache, latency, and error families. The client-facing DNS VIP continued resolving `grafana.bohdal.name` to `10.1.30.55` after the Cilium rollout.
- Three control-plane Cilium BGP sessions remained established. The worker session remained active because the gateway lacked a `.44` peer; PR #121 added the missing desired-state peer and its reviewed gateway plan was `1 add, 9 change, 0 destroy`.
- PR #126 added an explicit `apply_gateway` dispatch path that consumes the immutable plan from the same GitHub Actions run and uses the working Bitwarden integration. Dispatch run `29851783524` planned successfully but failed during apply because provider 1.99.1 sent RouterOS 7.21/7.22-incompatible `vrf` and `add-path-out` fields. The failure matches open upstream issues `#944` and `#959`; upstream fix PR `#910` is not yet merged or released.
- The failed apply did not interrupt the three existing control-plane sessions, which remained established with their prior uptime. The worker session remained active. Do not retry the unchanged plan because it will repeat unsupported updates against existing IP addresses and BGP connections.

## Dashboard acceptance

Acceptance completed on 2026-07-21 after PR #122:

- Flux `observability-dashboards` applied exact Git revision `2c45941` and reported Ready. Its generated 32 KiB ConfigMap carried `grafana_dashboard="1"` and contained all eight committed JSON files.
- Grafana's authenticated search API returned UIDs `sk-network`, `sk-apc-ups`, `sk-synology`, `sk-proxmox`, `sk-dns`, `sk-ingestion`, `sk-cilium-bgp`, and `sk-syslog` as dashboard objects.
- Grafana's dashboard API reported every object as provisioned and returned the expected 33 panels in total. The dashboard sidecar and Grafana logs contained no recent provisioning errors.
- All 46 committed PromQL expressions executed successfully against live VictoriaMetrics. Empty results remain expected only where the device-specific SNMP collectors are not yet deployed; the dedicated Proxmox collector is now live.

## Grafana LAN acceptance

Acceptance completed on 2026-07-21. PRs #114, #115, and #116 introduced dependency-ordered certificate issuance, direct HTTPS exposure, split DNS, and strict self-monitoring:

- Flux `observability-base`, `observability-grafana-tls`, `observability-metrics`, and `dns` reported Ready at Git revision `7470942`. The metrics Helm release upgraded successfully to revision 7 for LAN exposure and revision 8 for the HTTPS scrape correction.
- The shared namespace moved from metrics ownership to independent `observability-base` ownership without deletion or label loss. The resulting dependency graph is acyclic on a fresh cluster: base creates the namespace, cert-manager issues `grafana-tls`, and metrics mounts the Ready Secret.
- Production ACME order `grafana-1-1769370120` became valid. Secret `grafana-tls` has type `kubernetes.io/tls` and only `tls.crt` and `tls.key`; the ECDSA certificate covers `grafana.bohdal.name` and `grafana.internal.bohdal.name` and expires on 2026-10-18.
- Cilium allocated only fixed VIP `10.1.30.55` to Service `metrics-grafana`. The Service exposes HTTPS on TCP 443, forwards to Grafana port 3000, and limits LoadBalancer sources to `10.0.0.0/8`.
- Blocky returned both Grafana names as `10.1.30.55` and reverse lookup of `.55` as `grafana.bohdal.name`.
- The LAN health endpoint returned Grafana 13.1.0 with database `ok` over a browser-trusted chain. Anonymous organization access returned HTTP 401, authenticated admin access succeeded without exposing credentials, the LAN alias redirected to the canonical name, and plaintext port 80 was unreachable.
- VictoriaMetrics and VictoriaLogs datasource health checks both returned `OK` through the LAN TLS endpoint.
- Grafana ran Ready on the general-purpose worker with zero restarts. Its stack-owned VMServiceScrape uses HTTPS, validates the public certificate against `grafana.bohdal.name`, returned `up=1`, and stopped the previous plaintext scrape handshake errors.
- The DNS renderer now derives changed-zone serials from the committed baseline, so repeated renders are idempotent and `dns-check` can pass before commit.

## Grafana Cloudflare acceptance

Acceptance completed on 2026-07-22 after PRs #134 and #135:

- The shared tunnel routes only `grafana.bohdal.name` to `https://metrics-grafana.observability.svc.cluster.local:443`, supplies the canonical host name for HTTP and TLS validation, and retains the terminal `http_status:404` rule.
- Public DNS is a proxied CNAME to the stack-owned tunnel. A request pinned to a public Cloudflare edge returned HTTP 302 to `bohdy.cloudflareaccess.com/cdn-cgi/access/login/grafana.bohdal.name`, proving that unauthenticated internet traffic stops at Access rather than reaching Grafana.
- The self-hosted Access application permits exactly the Bitwarden-managed Gmail identity, accepts only the existing Google identity provider, redirects directly to that provider, and has one default-deny-compatible allow policy requiring the same Google login method.
- Independent Cloudflare-managed MFA is disabled for this single-user application. The owner must retain strong authentication on the Google account; Grafana authentication remains enabled behind Access.
- Split DNS remains independent of Cloudflare. A request pinned to LAN VIP `10.1.30.55` returned Grafana 13.1.0 with database `ok` over HTTPS.
- Production workflow runs `29924453217` and `29928401304` applied the initial publication and MFA simplification from immutable reviewed plans. The latter reported `0 added, 1 changed, 0 destroyed`, and a post-apply authenticated OpenTofu plan reported no changes.
- Both `cloudflared` replicas and Grafana were Ready during final acceptance. Grafana had zero restarts; the tunnel replicas retained six historical restarts each from more than four hours earlier and logged no errors during the 30-minute acceptance window.

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

Grafana probe acceptance completed on 2026-07-21 after PR #117:

- Flux `observability-blackbox` applied Git revision `23aeb6e` and reported Ready. The new VMStaticScrape was operational.
- Blackbox connected through real VIP `10.1.30.55` while supplying `grafana.bohdal.name` for the HTTP Host header and TLS SNI.
- The Grafana job reported `up=1`, `probe_success=1`, HTTP status 200, a certificate-expiry sample matching the issued certificate, and a current probe duration of approximately 94 ms.
- The existing sustained `BlackboxProbeFailed` critical rule covers Grafana without duplicate alert definitions. No Grafana probe alert was active during acceptance.
- Blackbox Exporter remained Ready on the worker with zero restarts, its Cilium policy reported valid, and recent logs contained no errors.

External HTTPS probe acceptance completed on 2026-07-22:

- The explicit stable target connects directly to Cloudflare's documented `1.1.1.1` anycast address while supplying `one.one.one.one` for the HTTP Host header and TLS SNI, avoiding broad DNS or network egress.
- VictoriaMetrics reported `up=1`, `probe_success=1`, HTTP status 200, a valid TLS certificate-expiry sample, and a current probe duration of approximately 33 ms with stable `cluster="sk-talos"`, `site="sk"`, and `instance="cloudflare-one"` labels.
- Blackbox Exporter remained Ready with zero restarts and no errors in its recent logs. The existing sustained `BlackboxProbeFailed` critical rule covers this always-on target.

## Alerting acceptance

Acceptance completed on 2026-07-20. PRs #109 and #110 introduced local coverage, bounded Alertmanager behavior, and a correction for one invalid upstream meta-alert:

- Flux `observability-alerting` and `observability-metrics` reported Ready at Git revision `6d4a4e5`; the metrics Helm release upgraded successfully to revision 5.
- All four Flux controller targets and the cert-manager controller reported `up=1`. The local VMRule was operational, every local rule evaluated with health `ok`, and no local warning or critical alert was unexpectedly active.
- Local rules cover sustained Blackbox failure, derived Vector syslog throttle drops, Vector discarded events and buffer pressure, VictoriaLogs dropped rows and read-only storage, Flux reconciliation failure, and certificate expiry.
- Talos-only scheduler and controller-manager rules were disabled because their private metrics endpoints are intentionally unavailable. The resulting false `KubeSchedulerDown` and `KubeControllerManagerDown` alerts cleared.
- The chart's generic `RecordingRulesNoData` alert was disabled because `count:up0` correctly emits no sample while every target is healthy. The other 248 live rules remained loaded after the change, and the stale false alert cleared from Alertmanager.
- The initial live Alertmanager configuration passed `amtool` validation with one blackhole receiver and three inhibition rules. A temporary matching critical and warning pair proved that the warning was suppressed while the critical remained active; both test alerts were then expired.
- Grafana provisioned exactly one read-only Alertmanager data source. Its server-side proxy reached Alertmanager 0.32.1 successfully; the generic health endpoint is not implemented for Grafana's built-in Alertmanager data-source type and returns `plugin.unavailable`.
- All serving metrics pods were Ready after reconciliation. Grafana and node exporters had zero restarts; kube-state-metrics and the operator retained historical restart counts from the earlier Kubernetes API audit rollout.
- PR #124 enabled critical Telegram delivery through native `bot_token_file` and `chat_id_file` references to the mounted Secret. No credential value is present in Helm output or the generated Alertmanager configuration.
- Flux `observability-metrics` and `observability-alerting` applied exact revision `60fede7`; the metrics Helm release reached revision 9. Alertmanager 0.32.1 and its config reloader remained Ready with zero restarts, runtime `amtool` validation succeeded, and config reload completed under the valid Cilium egress policy.
- The policy permits internal HTTPS/kube-apiserver access for config sidecars, resolves only `api.telegram.org` through kube-dns, and allows external HTTPS only to that FQDN. The accepted `10.0.0.0/8` internal boundary accommodates Cilium's translated Kubernetes API backend.
- A synthetic critical alert produced one firing and one resolved Telegram notification. `alertmanager_notifications_total{integration="telegram"}` advanced from 0 to 2, every Telegram failure-reason counter remained zero, and no notification error appeared in recent logs.
- A synthetic warning remained active through the one-minute group delay without increasing the Telegram counter, proving the channel receives only critical alerts. Both synthetic alert groups were then expired, leaving zero active acceptance alerts.
- Discord critical-and-warning delivery is configured from the dedicated Bitwarden webhook. On 2026-07-29, the mounted notification Secret contained the three expected keys without exposing values. A self-expiring synthetic set proved two critical alerts with the same group labels were grouped, a warning reached only Discord, and an equivalent warning was inhibited by its critical alert. Firing notifications advanced Discord from 63 to 66 and Telegram from 8 to 10. After the configured 10-minute group interval, resolved notifications advanced Discord from 66 to 69 and Telegram from 10 to 12. Every Discord and Telegram failure-reason counter remained zero, recent Alertmanager logs contained no delivery errors, and no acceptance alert remained active. Info alerts remain retained in Alertmanager and Grafana without push delivery.

## VictoriaLogs acceptance

Acceptance completed on 2026-07-17:

- Flux `observability-logs` and the VictoriaLogs Helm release reported Ready on chart 0.13.9 with VictoriaLogs v1.52.0.
- The live StatefulSet used `--retentionPeriod=30d` and `--retention.maxDiskUsagePercent=85`.
- Retained 50 GiB PV `pvc-55399cea-d465-4439-8517-423dca5704aa` was Bound through `synology-iscsi-retain`.
- A synthetic JSON-stream record was ingested with stable `cluster`, `site`, and `source_type` fields and remained queryable after VictoriaLogs pod recreation.
- VictoriaLogs self-monitoring reported `up=1` in VMSingle with `cluster="sk-talos"` and `site="sk"`.
- Grafana loaded signed plugin `victoriametrics-logs-datasource` version 0.29.0, its real-query health check returned OK, and its data-source query API returned the persisted acceptance record.
- VictoriaLogs and Grafana remained Ready with zero restarts after acceptance.

## MikroTik SNMP acceptance

Acceptance completed on 2026-07-22 for the production SNMPv3 path:

- OpenTofu imported the existing RouterOS v2c and v3 communities with `2 imported, 0 added, 0 changed, 0 destroyed`; the follow-up plan reported no changes.
- Both communities are enabled, read-only, and scoped to `10.0.0.0/8`. The production v3 profile uses RouterOS-supported SHA1 authentication with AES privacy.
- Flux `observability-snmp` applied Git revision `c0a3384` and reported Ready after the polling target was corrected from the REST management address `10.1.100.1` to the RouterOS SNMP listener at `10.1.20.1`.
- Direct v3 discovery across the `system`, `if_mib`, and `mikrotik` modules returned 447 samples across 95 metric names, including system uptime, high-capacity interface counters, and MikroTik vendor metrics.
- VictoriaMetrics reported the production target and exporter self-scrape at `up=1`, with stable `cluster="sk-talos"`, `site="sk"`, `instance="mikrotik-gw"`, and `vendor="mikrotik"` labels.
- The production target exposed 2,464 series, below its 10,000-series limit. The exporter pod was Ready with zero restarts and no scrape errors after the target correction.
- Exporter arguments, rendered manifests, logs, and metrics contained credential variable names or masked values only; the four actual Bitwarden values were absent from the Git diff.
- The optional v2c compatibility probe times out even though Bitwarden, the Kubernetes Secret, OpenTofu state, and the live RouterOS community agree. Production remains on healthy SNMPv3; diagnose v2c without weakening or interrupting that path.

## Synology SNMP acceptance

Acceptance completed on 2026-08-02 after PRs #176, #177, and #178:

- The exporter sends the SNMPv2c community from an init-container-rendered auth file on a memory-backed volume. The community is absent from Git, ConfigMaps, pod arguments, and the main exporter container environment.
- The Synology DSM SNMPv2c `system`, `if_mib`, and `synology` modules all returned successful metrics through the exporter from the Kubernetes worker source.
- Flux `observability-snmp` applied Git revision `00fd064` and reported Ready after the init container completed with no restarts.
- The production `snmp-synology` scrape polls `10.1.100.10` every 60 seconds with stable `instance="synology"`, `vendor="synology"`, and `availability="always-on"` labels. VictoriaMetrics reports `up=1` and 1,609 active series, below its 10,000-sample and 10,000-series bounds.

## APC USB UPS acceptance

Acceptance completed on 2026-08-02 through the accepted Synology target:

- Synology's vendor MIB exposes the USB-connected APC Back-UPS XS 950U through its existing `synology` module. It returns model, charge, runtime, load, input voltage, and online/on-battery status; the direct APC and generic UPS MIBs correctly return no device PDUs because there is no UPS network management card.
- The APC dashboard queries those verified Synology UPS metric families and no longer renders unavailable network-card metric families.
- `APCUPSOnBattery` pages only after two continuous minutes on battery, and `APCUPSLowRuntime` pages after two continuous minutes below ten minutes of runtime. Both are critical, actionable conditions routed through the existing Telegram and Discord policy.
- The `apc-ups` inventory entry records that collection is mediated by the Synology target; no duplicate poll or stale DHCP-reservation endpoint is enabled.

## Monitored-device DHCP acceptance

Acceptance completed on 2026-07-23 after PR #148 established declarative RouterOS reservations for the two initially dynamic monitoring targets:

- Production workflow run `29996032535` created an immutable plan containing only two one-shot `make-static` helpers and the imported APC and Brother lease resources. Its apply completed successfully with no destroy action.
- RouterOS lease `*158A` remains bound at `10.1.10.43` on `server10` for the APC UPS, and lease `*135B` remains bound at `10.1.10.13` on the same server for the Brother printer. Both now report `dynamic=false` and retain their descriptive comments.
- A post-apply targeted OpenTofu plan refreshed both helpers and both managed lease resources and reported no changes. The provider still emits an unrelated unsupported `age`-field warning when reading RouterOS leases.
- Address stability is no longer an SNMP inventory blocker for either target. Their authentication profile and Bitwarden bootstrap blockers remain; do not enable a collector until those device-side credentials and read-only SNMP settings are confirmed.

## UniFi SNMP discovery

Discovery completed on 2026-07-23; initial production collection was enabled on 2026-08-02:

- The legacy controller at `unifi.bohdal.name` accepted the dedicated Bitwarden administrator through its legacy API. Its controller-level SNMPv2c setting is enabled with the shared community, whose value is absent from command output and Git.
- Read-only discovery returned `sysName.0` values `AP-1PP`, `AP-1NP`, and `AP-temp`; all three targets report U7-Pro firmware `8.6.11.18870` and the Ubiquiti enterprise object identifier.
- OpenTofu now owns narrow worker-to-AP-management UDP/161 and SNMP reply exceptions. A direct exporter probe to `AP-1PP` at `10.1.102.10` returned all configured modules from the worker path: 32 `system`, 1,241 `if_mib`, and 181 `ubiquiti_unifi` PDUs.
- All three UniFi APs are enabled after independent full-profile probes. The shared controller-managed SNMPv2c profile works for each device, so no extra AP-specific Bitwarden secret is needed.
- Flux applied the `snmp-unifi-ap-1pp` VMStaticScrape at revision `15202fe`. VictoriaMetrics reported `up=1` with the expected cluster, site, instance, vendor, and availability labels, and 1,387 series, below the 10,000-series limit.
- Flux applied the `snmp-unifi-ap-temp` VMStaticScrape at revision `61c1e08`. VictoriaMetrics reported the same expected labels with `up=1` and 1,543 series, below the 10,000-series limit.
- Flux applied the `snmp-unifi-ap-1np` VMStaticScrape at revision `d544d38`. VictoriaMetrics reported the same expected labels with `up=1` and 1,542 series, below the 10,000-series limit.

## UniFi controller migration

Staging began on 2026-07-24 after the internal DNS and DHCP rollout completed. Restore and device-service cutover are accepted as of 2026-08-02:

- A fresh native backup `10.1.89.unf` was created on the legacy controller through its private authenticated API. It is 15.2 MB and remains outside Git and Kubernetes secret storage.
- The Talos `unifi` Flux component provisions a private restore stage with retained Synology iSCSI volumes, a controller image digest matching the backup source, MongoDB 8.0.28, and separately bootstrapped Bitwarden credentials for MongoDB root and the least-privilege UniFi database user.
- The application user is created in MongoDB's `admin` authentication database, with roles restricted to `unifi`, `unifi_stat`, `unifi_audit`, and `unifi_restore`; this matches the controller's supported URI while preserving database-level least privilege.
- The administrator console remains the private ClusterIP `unifi-console` service. The dedicated device service now owns Cilium LoadBalancer VIP `10.1.30.1` for AP inform, STUN, and discovery only; no Cloudflare route, DNS record, or Access application has been added for the console.
- A read-only query through the least-privilege application user found both `default` and `super` sites, one SNMP settings record, and three adopted AP records: `AP-1NP` (`10.1.102.11`), `AP-1PP` (`10.1.102.10`), and `AP-temp` (`10.1.102.12`). The setting value was not read. The independently verified `AP-1PP` SNMPv2c scrape proves the deployed device-side compatibility profile works through the new worker VLAN path.
- Initial live reconciliation showed that MongoDB requires `CHOWN`, `DAC_OVERRIDE`, `SETGID`, and `SETUID` for first-run setup. The LinuxServer controller's `s6` phase fails to render its packaged template under no-new-privileges, so it uses the supported image initialization context. Pod-level RuntimeDefault seccomp, private-only exposure, and Cilium policy remain enforced.

## Proxmox acceptance

Acceptance completed on 2026-07-23 after PRs #140 through #146 introduced the collector and corrected issues found through live verification:

- OpenTofu owns passwordless user `observability@pve` in dedicated group `observability`, privilege-separated token `exporter`, and propagated root `PVEAuditor` ACLs for both the group and token. The live API returned both ACL entries, and the token's effective root permissions included `Sys.Audit` with seven read-only privileges.
- Production workflow run `29992291213` created the group and group ACL, updated user membership, forgot the provider's phantom parent-user ACL state entry without destroying it, and reported `2 added, 1 changed, 0 destroyed, 1 forgotten`. The fail-closed Bitwarden token handoff check passed.
- Provider 0.106.0 projects the separately managed group ACL into its deprecated inline group field. PR #146 added a narrowly scoped lifecycle ignore so the dedicated ACL resource remains authoritative; both local and attached PR plans subsequently reported no changes.
- Flux `observability-proxmox` deployed one Ready exporter replica to `sk-talos-worker-1`. The pod used the pinned multi-architecture Prometheus PVE Exporter 3.8.2 digest, had zero restarts, disabled service-account token mounting, retained a read-only root filesystem, and used a bounded memory-backed `/tmp` only for Gunicorn worker state.
- The static API address is mapped to certificate-valid hostname `pve.sk.bohdal.name` inside the pod. HTTPS validates through the committed Proxmox root CA, and the Cilium policy permits no DNS egress and only `10.1.100.201:8006` for API collection.
- VictoriaMetrics reported `up=1` for both the exporter self-scrape and logical Proxmox target. The target exposed 626 series across 28 `pve_*` families, all with `cluster="sk-talos"`, `site="sk"`, and `instance="pve"`, below the 5,000-series limit.
- Live families included node, guest, storage, uptime, resource use, and backup coverage. Acceptance measured one node, 15 guests, four storage objects, and 15 guests not covered by a configured backup job; exporter request errors did not increase after the ACL correction.
- Every Proxmox dashboard expression matched a live metric family, including `pve_up`, memory, disk, and `pve_not_backed_up_total`. No API token value appeared in manifests, pod arguments, files, logs, metrics, or the Git diff.

## Flow collection stage

The IPFIX flow collection stage follows `docs/flow-collection-design.md`. It ships in five stacked milestone PRs that merge in order:

1. Collector pipeline: goflow2 and ClickHouse manifests, Vector handoff, and the `observability-flow-collector` Flux component.
2. Grafana: pinned ClickHouse plugin and datasource, `sk-flow` dashboard, ingestion-health panels, and the flow alert group.
3. Gateway export: RouterOS traffic-flow resources and the mutually exclusive `apply_gateway_ipfix` workflow path.
4. Adaptive GeoIP: local GeoLite2 City refresh, ClickHouse IP_TRIE lookup, and source/destination Geomap layers.
5. Documentation promotion of the design contract.

Merge sequence and bring-up:

- Merge PRs 1-3 in order. The collector pipeline deploys `clickhouse`, `goflow2`, and the `clickhouse-ddl` Job in the `observability` namespace; the Job applies the committed `flows.flow` schema and 30-day TTL before writers start. goflow2 is reachable on the reserved `10.1.30.57` VIP, UDP/2055.
- `FlowCollectorRecordsStopped` fires warning-level from collector bring-up until the gateway exports flows; it is the intended rollout signal, not noise.
- On `main`, dispatch the OpenTofu workflow with only `apply_gateway_ipfix` enabled. The targeted plan is reviewed and applied against the production environment; the workflow applies only the uploaded immutable artifact.
- Verify WAN records arrive with expected fields (sampler address from the gateway, `etype`/`proto` names, `src_addr`/`dst_addr` populated), the `sk-flow` dashboard returns data, and ingestion-health panels show collector packets and ClickHouse sink deliveries.
- Confirm the UniFi console remains on `.56` and the collector VIP is unique in live Cilium LB IPAM and the committed DNS inventory.
- Create the Bitwarden-backed `maxmind-geoip` Secret, allow the non-blocking `observability-flow-geoip` Kustomization to run, and verify the bootstrap Job loads `flows.ip_geo` without credential output.
- Verify the source and destination Geomaps show country markers for small or uncertain locations and approximate city markers only for large countries within the configured 100 km accuracy radius.

Flow acceptance completed on 2026-08-07 after worker expansion and the collector target cutover: RouterOS exported `ether8` and every routed VLAN through `10.1.30.57:2055`, ClickHouse contained active `flows.flow` and `flows.flow_analytics` data, the GeoIP dictionary tables were loaded, and the six-node Cilium path advertised the collector VIP through the control-plane BGP peers. The scheduled GeoIP refresh that ran during the earlier outage failed and requires one successful post-recovery run before the refresh path is considered fully accepted.

Acceptance criteria per the design contract:

- Records from the WAN path present with expected fields.
- `TTL timestamp + INTERVAL 30 DAY` present on `flows.flow` and survives a ClickHouse restart.
- VIP unique; UniFi console remains on `.56`.
- `apply_gateway_ipfix` mutual exclusion and immutable apply path work.
- `observability-capacity` quota remains healthy with the added 100 GiB claim and memory requests.
- No dropped records, repeated restarts, or unexpected exposure during soak.
- GeoIP refresh failures leave the last successful dictionary data available and do not block flow ingestion or dashboard provisioning.

Rollback: suspend or revert the `observability-flow-collector` Flux Kustomization while retaining the ClickHouse PVC. Never delete the retained PV or the Synology LUN as part of routine rollback; the gateway target removal is a separate reviewed OpenTofu apply.

## Selected-host and routed VLAN extension

This follow-up extends the accepted WAN flow stage to routed traffic between VLANs and adds selected-host analytics to `sk-flow`. The gateway flow interface list is derived from `vlans.auto.tfvars` and includes `ether8` plus each routed VLAN interface; the bridge is excluded so same-VLAN switching remains outside scope. The ClickHouse DDL Job creates `flows.flow_analytics`, which centralizes the five-LAN-CIDR policy used by Grafana.

Before production apply, verify the live RouterOS traffic-flow interface behavior and compare record counts and byte totals before and after the interface-list change. Confirm that a known routed VLAN exchange and WAN exchange each produce one expected flow path, with no duplicate records. Then verify the Grafana dropdown, manual override, All mode, inbound/outbound panels, selected-host Sankey, recent-flow table, and direction-aware external Geomaps.

Acceptance requires no unexpected storage pressure, no dropped Vector-to-ClickHouse deliveries, no private addresses in GeoMap results, and no credential or raw-flow leakage in workload logs. Same-VLAN device-to-device traffic requires a separate switch or access-point flow telemetry design.

## Remaining stages

The first observability release is accepted. Follow-up work must use a fresh branch for each coherent deferred item. Stop progression on dropped data, repeated restarts, storage or worker pressure, unexpected public exposure, secret leakage, or excessive alert noise.

## Secret inventory

Bitwarden Secrets Manager remains the source of truth. Kubernetes Secrets are manually bootstrapped with shell tracing disabled and values passed directly from `bws` without echoing or writing them to the repository.

Known item names needed by the rollout are:

- `SK-TALOS-GRAFANA-ADMIN-PASSWORD`: Grafana administrator password only
- `SK-TALOS-CLOUDFLARED-TOKEN`: shared Cloudflare Tunnel connector token only
- `CLOUDFLARE_API_TOKEN`: narrowly scoped DNS-01 token only
- `SK-TALOS-SYNO-CSI`: Synology CSI DSM password only
- `TELEGRAM_BOT_TOKEN`: Telegram bot token only
- `TELEGRAM_CHAT_ID`: Telegram group chat ID only
- `SK-TALOS-SNMP-V2-COMMUNITY`: SNMPv2c community string only
- `SK-TALOS-SNMP-V3-USERNAME`: SNMPv3 security name only
- `SK-TALOS-SNMP-V3-AUTH-PASSWORD`: SNMPv3 authentication password only
- `SK-TALOS-SNMP-V3-PRIV-PASSWORD`: SNMPv3 privacy password only
- `SK-TALOS-GRAFANA-ACCESS-EMAIL`: exact Gmail address allowed by Cloudflare Access only
- `SK-TALOS-PROXMOX-EXPORTER-API-TOKEN`: full OpenTofu-generated `observability@pve!exporter=<secret>` API token only
- `SK-TALOS-UNIFI-CONTROLLER-USERNAME` (`bb9869b1-c721-46b9-a07b-b49000a68fb1`): UniFi Network administrator username used only to configure and verify access-point SNMP
- `SK-TALOS-UNIFI-CONTROLLER-PASSWORD` (`8fa7fee1-3612-42e7-895f-b49000a68ffd`): matching UniFi Network administrator password only
- `SK-TALOS-UNIFI-MONGODB-ROOT-PASSWORD` (`989143be-3e3e-4a66-b85c-b4910055b1bf`): Talos UniFi MongoDB root password used only to initialize the database
- `SK-TALOS-UNIFI-MONGODB-APPLICATION-PASSWORD-ROTATED` (`be72e505-dffe-41ac-aca8-b49100b86d86`): replacement Talos UniFi least-privilege MongoDB application-user password only
- `SK-TALOS-MAXMIND-GEOLITE2-ACCOUNT-ID`: MaxMind Account ID only, used by the local GeoLite2 City database updater
- `SK-TALOS-MAXMIND-GEOLITE2-LICENSE-KEY`: MaxMind license key only, used by the local GeoLite2 City database updater
- `SK-TALOS-SYNO-MONITORING-USERNAME` (`23d42b1f-323c-4405-b36c-b49000a69047`): dedicated temporary Synology DSM administrator setup username used only to enable and verify SNMP
- `SK-TALOS-SYNO-MONITORING-PASSWORD` (`8d9d92fb-aada-4dab-997d-b49000a690a7`): matching temporary Synology DSM administrator setup password only
- `SK-TALOS-APC-UPS-USERNAME` (`88990a45-9e37-4a66-a7c9-b49000a690e7`): APC Network Management Card administrator username used to configure and verify SNMP
- `SK-TALOS-APC-UPS-PASSWORD` (`b8013434-6712-41f2-b113-b49000a69135`): matching APC Network Management Card administrator password only
- `SK-TALOS-BROTHER-ADMIN-PASSWORD` (`a0c5ba12-f102-43ca-b8b7-b49000a69182`): Brother printer web-administrator password only
- `SK-TALOS-DISCORD-WEBHOOK` (`306e8dc6-2df2-4a9e-86ec-b49000a691c7`): complete Discord webhook URL only

The eight device and Discord items initially contain the literal placeholder `__REPLACE_BEFORE_USE__`. Replace every placeholder with the real single-value credential before enabling its dependent configuration; the placeholder is intentionally invalid and must never be used as a working secret.

DSM provides no narrower user privilege for changing its system-wide SNMP service. After SNMP acceptance, disable or remove the dedicated temporary Synology setup account because the deployed SNMP exporter uses its SNMP credential rather than the DSM account.

Create dedicated Bitwarden items before the stages that require device-specific SNMP credentials or the Discord webhook. Document each item's value contract next to its bootstrap procedure; never store a whole configuration block when the documented contract calls for a single credential.

## Deferred debt

Keep the design document's follow-up list authoritative. In particular, Brother printer SNMP acceptance, traces, Moonraker/Klipper monitoring, UniFi Poller, automated Bitwarden reconciliation, raw telemetry backup, NetFlow or sFlow, and an external dead-man monitor remain deferred. The Brother printer requires an administrator-password reset before configuring or confirming read-only SNMPv2c with the existing shared profile; once it is online, re-probe `system` and `printer_mib` from the exporter before enabling its bounded intermittent scrape. RouterOS v2c compatibility diagnosis is also follow-up debt; the accepted production scrape uses SNMPv3. Reassess the Proxmox ACL `removed` block and group `acl` lifecycle ignore when upgrading beyond provider 0.106.0; remove either workaround only after a live no-destroy plan and effective-permission verification.
