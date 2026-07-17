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

1. Deploy Vector for Kubernetes container logs with exclusion annotations, bounded disk buffering, stable fields, and loop prevention.
2. Add the fixed Cilium logging VIP with TCP/UDP syslog and original sender preservation.
3. Verify parsing failures, sender and receipt timestamps, rate limits, buffer pressure metrics, and end-to-end log persistence before adding Talos and audit sources.

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

After metrics acceptance, use a fresh branch from current `main` for each coherent stage:

1. Deploy VictoriaLogs Single with a retained 50 GiB volume and 30-day retention.
2. Deploy Vector as a DaemonSet for Kubernetes logs, then add TCP/UDP syslog on a fixed Cilium LoadBalancer VIP with original sender preservation.
3. Add Talos service and kernel log forwarding and verify the supported Talos audit-event delivery path without request or response bodies.
4. Add SNMP Exporter, committed target inventory, and reviewed SNMPv2c/SNMPv3 modules for MikroTik, UniFi APs, Synology, APC UPS, and Brother printer; treat the printer as intermittent.
5. Add the read-only Proxmox exporter and Blackbox Exporter probes.
6. Add focused dashboards, actionable alert rules, inhibition, Telegram delivery for critical alerts, Discord delivery for critical and warning alerts, and no push delivery for info alerts.
7. Publish only Grafana through a fixed LAN VIP, browser-trusted TLS, split DNS, the shared Cloudflare Tunnel, and Cloudflare Access restricted to the approved Gmail identity with MFA.
8. Run the complete acceptance suite from `docs/observability-design.md`, then update this checkpoint with measured ingestion, resource use, and any deferred debt.

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
