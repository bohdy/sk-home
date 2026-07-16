# Prefer VictoriaLogs for logs

Home Infrastructure Observability will use VictoriaLogs as the v1 log and syslog backend instead of Loki, with Vector as the collector and Grafana plus its pinned VictoriaLogs data source plugin as the UI. VictoriaLogs will retain Kubernetes, Talos, audit, network syslog, and DNS query logs for 30 days. This keeps metrics and logs in the VictoriaMetrics family while Vector provides the source handling, enrichment, buffering, and rate limiting required by the home infrastructure.
