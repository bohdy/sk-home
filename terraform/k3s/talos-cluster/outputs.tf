output "talos_config" {
  # Mark the client configuration sensitive because it contains Talos admin
  # credentials that can control every node in the cluster.
  description = "Sensitive talosconfig content for talosctl access."
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "kubeconfig" {
  # Mark kubeconfig sensitive because it contains Kubernetes client
  # credentials for the new control plane.
  description = "Sensitive kubeconfig content for Kubernetes access."
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "control_plane_nodes" {
  # This inventory is safe to print and helps operators verify which Proxmox
  # guests OpenTofu created without exposing access credentials.
  description = "Non-sensitive control-plane node inventory."
  value = {
    for node_key, node in var.nodes : node_key => {
      hostname = node.hostname
      ip       = split("/", node.ipv4_address)[0]
      vm_id    = node.vm_id
    }
  }
}

output "worker_nodes" {
  # Expose non-sensitive worker placement for post-apply health and scheduling
  # checks without requiring operators to parse the input map.
  description = "Non-sensitive worker node inventory."
  value = {
    for node_key, node in var.worker_nodes : node_key => {
      hostname = node.hostname
      ip       = split("/", node.ipv4_address)[0]
      vm_id    = node.vm_id
    }
  }
}

output "cluster_endpoint" {
  # Print the API endpoint separately so follow-up tooling can consume it
  # without parsing kubeconfig content.
  description = "Kubernetes API endpoint backed by the Talos VIP."
  value       = "https://${var.cluster_endpoint_vip}:6443"
}

output "proxmox_exporter_api_token" {
  # The provider returns only the secret value on creation. Remote state keeps
  # the complete credential so the apply workflow can hand it directly to the
  # dedicated Bitwarden item without exposing it in logs or repository files.
  description = "Sensitive full API token for the read-only Proxmox exporter identity."
  value       = "${proxmox_user_token.observability_exporter.id}=${proxmox_user_token.observability_exporter.value}"
  sensitive   = true
}
