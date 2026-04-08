# Publish stable non-secret service metadata for operators and sibling stacks.
output "namespace_name" {
  description = "Namespace that owns the Blocky workload."
  value       = kubernetes_namespace_v1.blocky.metadata[0].name
}

output "dns_service_ip" {
  description = "Static MetalLB IP used by the external Blocky DNS service."
  value       = var.dns_ip
}

output "metrics_scrape_target" {
  description = "In-cluster HTTP target that observability scrapes for Blocky metrics."
  value       = "${kubernetes_service_v1.blocky_metrics.metadata[0].name}.${kubernetes_namespace_v1.blocky.metadata[0].name}.svc.cluster.local:4000"
}

output "stack_context" {
  description = "Non-sensitive stack metadata for downstream consumers and validation."
  value = {
    project_name = var.project_name
    environment  = var.environment
  }
}
