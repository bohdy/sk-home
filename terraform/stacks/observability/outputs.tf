output "victoria_metrics_external_ip" {
  description = "Existing MetalLB IP preserved for external VictoriaMetrics ingestion."
  value       = var.victoria_metrics_external_ip
}

output "grafana_hostname" {
  description = "Public Grafana hostname preserved by the imported ingress."
  value       = var.grafana_hostname
}

output "stack_context" {
  description = "Non-sensitive stack metadata preserved for downstream consumers and linting."
  value       = local.common_tags
}
