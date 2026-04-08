# Observability

This stack replaces the Pulumi `sk-metrics` domain with import-oriented Terraform.

It owns the live `monitoring` namespace, VictoriaMetrics, vmagent, Grafana, Unpoller, blackbox-exporter, snmp-exporter, and the Helm-managed `kube-state-metrics` release.

The committed config payloads under `config/` and `dashboards/` intentionally match the current live cluster shape, including the simplified Grafana dashboard layout and the imported vmagent scrape config. Import the existing resources before the first apply.

The vmagent scrape configuration also includes the `blocky-dns-k3s` job that scrapes the dedicated Blocky DNS metrics service at `blocky-metrics.app-blocky-k3s.svc.cluster.local:4000`.

The VictoriaMetrics StatefulSet also carries a narrow lifecycle ignore for provider-synthesized PVC template metadata that would otherwise force a replacement of the retained live volume during import normalization.
