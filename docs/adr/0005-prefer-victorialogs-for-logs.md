# Prefer VictoriaLogs for logs

Home Infrastructure Observability will prefer VictoriaLogs as the v1 log and syslog backend instead of Loki, while keeping Grafana as the UI. This keeps metrics and logs in the VictoriaMetrics operator family, reduces the number of storage systems in the home lab, and leaves Loki as a fallback only if implementation research finds a concrete blocker in syslog ingestion, Kubernetes log collection, Grafana querying, retention, or operational maturity.
