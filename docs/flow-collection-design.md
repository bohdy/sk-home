# Flow collection design

This document is the implementation contract for IPFIX flow collection in the `sk-talos` cluster. It records the decisions agreed before manifests are introduced and now serves as the reference for the delivered component.

The design's follow-up debt list is authoritative for later flow-collection work; `docs/observability-design.md` and `docs/observability-rollout.md` reference this document instead of duplicating it.

## Goals

Collect IPFIX flow records from the MikroTik gateway, store them in a ClickHouse database inside the cluster, and expose flow analytics through provisioned Grafana dashboards. The pipeline should fit into the existing Home Infrastructure Observability pattern: plain Kubernetes manifests, Flux reconciliation, Cilium LoadBalancer exposure, and Synology iSCSI persistent storage.

Start with WAN traffic only. Design for inter-VLAN expansion without architectural changes.

## Non-goals

The first release excludes inter-VLAN flow collection, sFlow, NetFlow v5/v9, distributed ClickHouse (no Keeper, no sharding, no replication), automated ClickHouse backups, and downstream flow consumers beyond Grafana.

## Architecture

Deploy goflow2 as a single-replica in-cluster IPFIX collector. Expose it on a free fixed Cilium LoadBalancer IP with UDP/2055 for IPFIX ingestion from the MikroTik gateway. Use `externalTrafficPolicy: Cluster` — IPFIX records embed the exporter address in the `sampler_address` field, so network-layer source IP preservation is not required the way it is for syslog.

Deploy ClickHouse as a single-replica stateful database on a retained Synology iSCSI PVC.

goflow2 writes decoded flow records as newline-delimited JSON to stdout. The existing Vector `kubernetes_logs` source already collects every container stream on each node, so a new `route` transform selects only the goflow2 `flow` container's stdout, a `remap` parses and enriches records with stable identity labels, and the native ClickHouse sink (HTTP interface, `JSONEachRow` format) delivers them to ClickHouse. goflow2 diagnostics on stderr continue to VictoriaLogs as ordinary container logs.

Use Grafana as the only user-facing flow analytics surface. Provision the official `grafana-clickhouse-datasource` plugin and a dedicated `sk-flow` dashboard. Add goflow2 ingestion health to the existing `sk-ingestion` dashboard via VictoriaMetrics.

Run components in the existing `observability` namespace. Reconcile through a new Flux `Kustomization` named `observability-flow-collector` under:

```text
kubernetes/flux/observability/flow-collector/
kubernetes/flux/clusters/sk-talos/observability/flow-collector-kustomization.yaml
```

Depends on `observability-base`, `cilium`, and `storage-synology-csi`. Dashboard and datasource pieces may also depend on `observability-metrics`.

## Data pipeline

```text
MikroTik gateway (ether8)
  -> IPFIX UDP/2055
  -> goflow2 LB <free VIP in 10.1.30.0/24>
  -> goflow2 NDJSON stdout (kubernetes_logs source)
  -> Vector route flow container stdout
  -> Vector parse_flow remap
  -> Vector ClickHouse sink
  -> ClickHouse
  -> Grafana
```

goflow2 runs with `-format=json -transport=file` and an empty file destination, which writes newline-delimited JSON to stdout. Vector's existing `kubernetes_logs` source picks the stream up node-locally; a `route` transform sends only the `flow` container's stdout to a parse/enrich remap (`cluster`, `site`, `source_type`) and lets everything else continue to VictoriaLogs unchanged. goflow2 must not set `vector.dev/exclude=true` so the source still collects it.

Vector's ClickHouse sink (confirmed in Vector 0.57.0) uses `INSERT INTO flows.flow FORMAT JSONEachRow` over HTTP, supports batching, and can set `skip_unknown_fields` so extra goflow2 fields do not break inserts.

No intermediate queue, no Kafka, no auth between collector, Vector, and ClickHouse. Vector is already running on every node, so the transport path does not introduce a new long-lived workload family.

### Why not native goflow2 → ClickHouse

goflow2 v2.2.6 transports are only `file`/`stdout` and `kafka`. There is no native ClickHouse producer. The official sample path is GoFlow2 → Kafka → ClickHouse. This design deliberately reuses Vector instead of adding Kafka.

### ClickHouse ownership

Schema is owned by the repository, not by goflow2. Before any writes occur, an init Job or one-shot Job applies committed DDL:

```sql
CREATE DATABASE IF NOT EXISTS flows;

CREATE TABLE IF NOT EXISTS flows.flow (
    timestamp DateTime64(9),
    type LowCardinality(String),
    time_received_ns UInt64,
    sequence_num UInt64,
    sampling_rate UInt64,
    sampler_address String,
    time_flow_start_ns UInt64,
    time_flow_end_ns UInt64,
    bytes UInt64,
    packets UInt64,
    src_addr String,
    dst_addr String,
    etype LowCardinality(String),
    proto LowCardinality(String),
    src_port UInt16,
    dst_port UInt16,
    in_if UInt32,
    out_if UInt32,
    src_mac String,
    dst_mac String,
    flow_direction UInt8,
    icmp_name LowCardinality(String),
    csum UInt32
) ENGINE = MergeTree()
ORDER BY timestamp
TTL timestamp + INTERVAL 30 DAY DELETE;
```

The TTL is declared at table creation. Do not rely on post-insert `ALTER TABLE` or goflow2 auto-creating tables.

Exact column set may be adjusted at implementation to match the live goflow2 JSON mapping used for MikroTik IPFIX, but the ownership rule does not change: committed DDL first, writers second.

## MikroTik configuration

Manage IPFIX through OpenTofu in `terraform/network/gw/interfaces/` using:

- `routeros_ip_traffic_flow` — accounting on `ether8` (WAN); leave timeouts at RouterOS defaults unless measured need appears
- `routeros_ip_traffic_flow_ipfix` — IPFIX settings
- `routeros_ip_traffic_flow_target` — collector VIP:2055, version `ipfix`, `v9_template_refresh = 20`, `v9_template_timeout = "5m"`

Add workflow input `apply_gateway_ipfix` with an immutable targeted plan, production environment apply, and full mutual exclusion against `apply_gateway`, `apply_gateway_snmp`, `plan_gateway_snmp`, `apply_gateway_dhcp`, and `apply_cloudflare`.

These traffic-flow resources are separate from the currently blocked BGP resources and should not require the broken `vrf` / `add-path-out` path.

## Storage and retention

| Parameter | Value |
|-----------|-------|
| StorageClass | `synology-iscsi-retain` |
| PVC size | 100 GiB |
| Retention | 30 days via table TTL |
| Database | `flows` |
| Table | `flow` |

## Resource sizing

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| goflow2 | 50m | 250m | 64 MiB | 256 MiB |
| ClickHouse | 500m | 2000m | 1 GiB | 2 GiB |

Vector already runs on all four nodes; flow handoff adds configuration, not a new Deployment family.

Fit check against `observability-capacity` is required at acceptance. Current quota is 8 PVCs and 300 GiB storage; one additional 100 GiB claim is feasible but tight on recovery headroom.

## Kubernetes deployment

Plain manifests reconciled by Flux. Pin images by immutable digest with human-readable version comments:

- goflow2: `ghcr.io/netsampler/goflow2` pinned to **v2.2.6**
- ClickHouse: `clickhouse/clickhouse-server` pinned to **26.7** (prefer distroless variant when selecting the final digest)

### goflow2

- Single replica
- UDP/2055 LoadBalancer on a free VIP in `10.1.30.0/24`
- `loadBalancerSourceRanges: ["10.0.0.0/8"]`
- `externalTrafficPolicy: Cluster`
- `-format=json -transport=file` with no file path, emitting NDJSON on stdout; Vector collects it through the existing `kubernetes_logs` source
- Prometheus metrics ClusterIP plus VMAgent scrape
- Stateless; no PVC

### ClickHouse

- Single replica plus retained PVC
- ClusterIP HTTP 8123, and native 9000 only if needed
- Minimal server config; DDL applied by init/one-shot Job before writer pods start
- No password in v1

### Vector

No new Vector pods. Extend the existing Vector configuration with:

- A `route` transform on `kubernetes_logs` matching `.kubernetes.container_name == "flow"` and `.stream == "stdout"`, with the unmatched output continuing the existing `exclude_annotated` chain
- A `remap` transform that parses the flow JSON, adds `cluster`, `site`, and `source_type`, and sets the ingest timestamp
- A ClickHouse sink to `http://clickhouse.observability.svc.cluster.local:8123`, database `flows`, table `flow`, format `json_each_row`, `skip_unknown_fields: true`

The stdout handoff is node-local like every other container log, so it needs no shared volume, no host path, and no dependency on every node hosting goflow2; kubelet rotates the stream exactly as for any container log.

## Grafana integration

- Pin `grafana-clickhouse-datasource` **v4.20.0** on the metrics HelmRelease plugin list
- Provision a datasource to ClickHouse ClusterIP, database `flows`, no auth
- New `sk-flow` dashboard backed by ClickHouse SQL
- Extend `sk-ingestion` with goflow2 and Vector ClickHouse-sink health via VictoriaQL/VictoriaMetrics

## NetworkPolicy

- goflow2 ingress: UDP/2055 from `10.0.0.0/8`
- goflow2 egress: only what the chosen Vector handoff requires
- ClickHouse ingress: only authorized writers (Vector) and Grafana datasource path
- ClickHouse egress: none by default

## Alerting

Define exact PromQL only after measuring live metric names during bring-up. Intent:

| Alert | Severity | Intent |
|-------|----------|--------|
| `FlowCollectorDown` | Critical | goflow2 not Ready for about 5 minutes |
| `FlowCollectorRecordsStopped` | Warning | no received flows for about 10 minutes |
| `FlowCollectorWriteFailure` | Warning | Vector ClickHouse sink or insert errors rising |

## Security and secrets

No new Bitwarden secrets for v1. IPFIX is unauthenticated UDP inside the home-lab trust boundary. ClickHouse runs without authentication inside the cluster, matching VictoriaMetrics and VictoriaLogs. OpenTofu MikroTik credentials already exist.

## Network addresses

- IPFIX VIP: free address in `10.1.30.0/24`
- Do **not** use `10.1.30.56`; that VIP is already assigned to UniFi LAN console HTTPS and DNS `unifi A 10.1.30.56`
- Confirm against live Cilium LB IPAM and committed DNS inventory before commit

Known reserved VIPs at plan time:

- `10.1.30.1` UniFi device service
- `10.1.30.53` Blocky DNS
- `10.1.30.54` Syslog
- `10.1.30.55` Grafana
- `10.1.30.56` UniFi console

## Implementation order

1. Choose and reserve a free IPFIX VIP.
2. Deploy ClickHouse with retained PVC and DDL/TTL Job.
3. Deploy goflow2 with LoadBalancer Service and metrics scrape.
4. Wire Vector handoff and ClickHouse sink; prove inserts.
5. Configure MikroTik IPFIX through `apply_gateway_ipfix`.
6. Verify WAN flow records arrive with expected fields.
7. Provision Grafana plugin, datasource, `sk-flow`, and ingestion panels.
8. Add NetworkPolicy.
9. Add alerts with real metric names.
10. Promote this plan into `docs/flow-collection-design.md`, update `docs/observability-design.md`, and add a resumable stage to `docs/observability-rollout.md`.

Proceed between stages after automated validation and workload smoke tests pass. Stop progression on dropped data, repeated restarts, capacity pressure, secret leakage, unexpected public exposure, or excessive alert noise.

## Validation and rollback

- Records from the WAN path are present with expected fields
- TTL is present on `flows.flow` and survives ClickHouse restart
- VIP is unique; UniFi console remains on `.56`
- `apply_gateway_ipfix` mutual exclusion and immutable apply path work
- Observability quota remains healthy after the new PVC and memory requests

Rollback by suspending or reverting the Flux `observability-flow-collector` Kustomization while retaining the ClickHouse PVC. Never delete the retained PV or Synology LUN as part of routine rollback.

## Decisions agreed and locked

- Protocol: IPFIX
- Source device: MikroTik gateway only for v1
- Interface: `ether8` WAN first; inter-VLAN later via bridge or additional interfaces
- Storage engine: ClickHouse, 100 GiB, 30 days
- Transport: goflow2 JSON → Vector → ClickHouse sink; no Kafka in v1
- goflow2 version target: v2.2.6
- ClickHouse version target: 26.7 line
- Grafana ClickHouse plugin target: v4.20.0
- Namespace: `observability`
- Flux component: `observability-flow-collector`
- OpenTofu ownership of traffic-flow resources plus targeted `apply_gateway_ipfix`
- No new secrets in v1
- Dual Grafana surfaces: analytics plus ingestion health
- Plain manifests for collector and ClickHouse, not Helm
- `externalTrafficPolicy: Cluster` because exporter identity is embedded in IPFIX records

## Follow-up debt

- Inter-VLAN flow collection
- Materialized views or rollups
- ClickHouse backup strategy
- sFlow if non-MikroTik exporters appear
- Revisit ClickHouse auth if exposure broadens
- Revisit Vector handoff topology if single-replica file delivery is awkward with DaemonSet collectors
