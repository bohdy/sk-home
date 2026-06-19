# Adopt VictoriaMetrics for metrics

Home Infrastructure Observability will use VictoriaMetrics as the v1 metrics backend, deployed through VictoriaMetrics Operator with `VMSingle`, `VMAgent`, `VMAlert`, and `VMRule` resources. This keeps Grafana and Prometheus-compatible exporters as the user-facing and integration contract while avoiding the heavier Prometheus/Mimir path for a single home cluster that still needs efficient local retention and Kubernetes-native discovery.
