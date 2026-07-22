output "tunnel_id" {
  description = "Cloudflare UUID of the reusable sk-talos tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
}

output "connector_token" {
  description = "Sensitive token consumed by cloudflared connector replicas."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster.token
  sensitive   = true
}

output "grafana_public_hostname" {
  description = "Public Grafana hostname protected by Cloudflare Access."
  value       = cloudflare_dns_record.grafana.name
}

output "grafana_access_application_id" {
  description = "Cloudflare Access application UUID protecting Grafana."
  value       = cloudflare_zero_trust_access_application.grafana.id
}
