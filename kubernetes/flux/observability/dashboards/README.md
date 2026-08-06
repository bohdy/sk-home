# Focused Dashboards

This component provisions nine focused Grafana dashboards through the chart-managed dashboard sidecar. Every dashboard is committed as JSON, uses a stable datasource UID, and requires no runtime download or mutable community-dashboard ID. The `sk-flow` dashboard uses the provisioned `FlowClickHouseIaC` datasource to query `flows.flow` and includes separate source-to-destination Sankey panels ranked by total bytes and flow count; the remaining dashboards use `VictoriaMetrics`.

The network, DNS, ingestion, Cilium/BGP, syslog, Proxmox, Synology, and APC UPS dashboards use metric families verified in the live cluster. The USB-attached APC is collected through the Synology vendor MIB, not a separate direct UPS poll. The network dashboard may show no data until its remaining credential-gated collectors are enabled; provisioning it first does not make absent collectors appear healthy.

Panel queries intentionally aggregate away high-cardinality labels unless an operator needs the label for action. Hubble panels use only the low-cardinality protocol, reason, service, family, and flag labels allowed by the bootstrap configuration.

## Validation

```sh
kubectl kustomize kubernetes/flux/observability/dashboards
kubectl kustomize kubernetes/flux/observability/dashboards | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require the generated ConfigMap to carry `grafana_dashboard="1"`, all committed dashboard UIDs to appear through Grafana's search API, and representative panel queries to return without syntax errors. Empty results are acceptable only for the explicitly credential-gated SNMP dashboards.

Rollback by reverting or suspending the `observability-dashboards` Flux Kustomization. Dashboard removal does not affect stored telemetry or collectors.
