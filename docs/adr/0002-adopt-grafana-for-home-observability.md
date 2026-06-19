# Adopt Grafana for home observability

Home Infrastructure Observability will use Grafana as the primary UI, Prometheus-compatible metrics as the metrics contract, VictoriaMetrics-family backends for v1 metrics and logs, and Tempo deferred until instrumented applications make traces useful. This keeps the first implementation coherent across Kubernetes, network devices, DNS, synthetic checks, dashboards, and alerts while avoiding an OpenTelemetry-first design before there are application traces to justify it.
