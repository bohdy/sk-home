output "namespace_name" {
  description = "Namespace that owns the Blocky workload."
  value       = kubernetes_namespace_v1.blocky.metadata[0].name
}

output "service_ip" {
  description = "Static MetalLB IP preserved for the Blocky service."
  value       = var.dns_ip
}

output "stack_context" {
  description = "Non-sensitive stack metadata preserved for downstream consumers and linting."
  value = {
    project_name = var.project_name
    environment  = var.environment
  }
}
