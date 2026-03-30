# Publish stable platform outputs that other stacks or operators may need
# without leaking secret-bearing runtime inputs.

output "stack_context" {
  description = "Resolved root-module context for the k3s platform stack."
  value = {
    project_name = var.project_name
    environment  = var.environment
    common_tags  = local.common_tags
  }
}

output "server_ip" {
  description = "k3s control-plane IP for kubeconfig and agent join configuration."
  value       = local.server_ip
}

output "node_ips" {
  description = "Map of node name to static IP address for all k3s cluster nodes."
  value       = { for k, v in var.nodes : k => v.ip }
}
