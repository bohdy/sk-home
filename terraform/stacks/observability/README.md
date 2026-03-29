# Observability

This stack is the Terraform destination for the existing Pulumi `sk-metrics` domain.

The stack root is committed now so imports and parity work can happen inside `sk-home` without inventing another state boundary later. It will eventually own VictoriaMetrics, vmagent, exporters, unpoller, Grafana, and the related ConfigMaps and ingress objects.
