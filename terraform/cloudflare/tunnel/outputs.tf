output "tunnel_id" {
  description = "Cloudflare UUID of the reusable sk-talos tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
}

output "connector_token" {
  description = "Sensitive token consumed by cloudflared connector replicas."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster.token
  sensitive   = true
}
