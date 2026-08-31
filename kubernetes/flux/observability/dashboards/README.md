# Focused Dashboards

This component provisions ten focused Grafana dashboards through the chart-managed dashboard sidecar. Every dashboard is committed as JSON, uses a stable datasource UID, and requires no runtime download or mutable community-dashboard ID. The `sk-flow` dashboard uses the provisioned `FlowClickHouseIaC` datasource to query the repository-owned `flows.flow_analytics` view, supports an observed internal-IP dropdown plus an optional manual override, and reports selected-host flows, bytes, packets, peers, protocols, ports, paths, recent records, and direction-aware external geography; the remaining dashboards use `VictoriaMetrics`.

The network, DNS, ingestion, Cilium/BGP, syslog, Proxmox, Synology, APC UPS, and UniFi Controller dashboards use metric families verified in the live cluster. The USB-attached APC is collected through the Synology vendor MIB, not a separate direct UPS poll. The UniFi dashboard covers controller health, client totals, throughput, signal/noise by radio protocol, protocol distribution, and client channel distribution; SNMP continues to own AP device-level radio and channel detail. The network dashboard may show no data until its remaining credential-gated collectors are enabled; provisioning it first does not make absent collectors appear healthy.

Panel queries intentionally aggregate away high-cardinality labels unless an operator needs the label for action. Hubble panels use only the low-cardinality protocol, reason, service, family, and flag labels allowed by the bootstrap configuration.

The flow dashboard's internal policy covers routed VLAN networks `10.1.10.0/24`, `10.1.20.0/24`, `10.1.100.0/24`, `10.1.101.0/24`, and `10.1.102.0/24`; it deliberately excludes the WAN transit subnet. `All` scopes selected-host panels to any internal endpoint, while a non-empty manual IP override takes precedence over the dropdown and invalid or non-LAN values return no flow rows. Same-VLAN switched traffic is not visible through the gateway flow collector.

## Validation

```sh
kubectl kustomize kubernetes/flux/observability/dashboards
kubectl kustomize kubernetes/flux/observability/dashboards | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require the generated ConfigMap to carry `grafana_dashboard="1"`, all committed dashboard UIDs to appear through Grafana's search API, and representative panel queries to return without syntax errors. Empty results are acceptable only for the explicitly credential-gated SNMP dashboards and the flow Geomaps before the MaxMind bootstrap Job completes.

Rollback by reverting or suspending the `observability-dashboards` Flux Kustomization. Dashboard removal does not affect stored telemetry or collectors.
