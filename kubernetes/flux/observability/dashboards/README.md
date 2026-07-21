# Focused Dashboards

This component provisions eight focused Grafana dashboards through the chart-managed dashboard sidecar. Every dashboard is committed as JSON, uses the stable `VictoriaMetrics` datasource UID, and requires no runtime download or mutable community-dashboard ID.

The DNS, ingestion, Cilium/BGP, and syslog dashboards use metric families verified in the live cluster. The network, APC UPS, and Synology dashboards use names from the committed SNMP Exporter 0.30.1 generated configuration. The Proxmox dashboard uses the Prometheus PVE Exporter 3.8.2 metric contract. Those four dashboards may show no data until their credential-gated collectors are enabled; provisioning them first does not make the absent collectors appear healthy.

Panel queries intentionally aggregate away high-cardinality labels unless an operator needs the label for action. Hubble panels use only the low-cardinality protocol, reason, service, family, and flag labels allowed by the bootstrap configuration.

## Validation

```sh
kubectl kustomize kubernetes/flux/observability/dashboards
kubectl kustomize kubernetes/flux/observability/dashboards | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require the generated ConfigMap to carry `grafana_dashboard="1"`, all eight UIDs to appear through Grafana's search API, and representative panel queries to return without syntax errors. Empty results are acceptable only for the explicitly credential-gated SNMP and Proxmox dashboards.

Rollback by reverting or suspending the `observability-dashboards` Flux Kustomization. Dashboard removal does not affect stored telemetry or collectors.
