output "stack_context" {
  description = "Resolved root-module context for the Proxmox platform stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    site_name    = var.site_name
    common_tags  = local.common_tags
  }
}

output "cluster_ip" {
  description = "Existing Kubernetes control-plane IP preserved on the imported master VM."
  value       = local.cluster_nodes.k8s_master.ip
}

output "openclaw_vm_ip" {
  description = "Static IP preserved for the imported vm-openclaw guest."
  value       = local.openclaw_vm.ip
}

output "proxmox_metrics_server_id" {
  description = "Existing Proxmox metrics server name preserved for VictoriaMetrics ingestion."
  value       = proxmox_virtual_environment_metrics_server.victoria_metrics.id
}
