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

output "unifi_public_hostname" {
  description = "Public UniFi hostname protected by Cloudflare Access."
  value       = cloudflare_dns_record.unifi.name
}

output "unifi_access_application_id" {
  description = "Cloudflare Access application ID enforcing the UniFi owner policy."
  value       = cloudflare_zero_trust_access_application.unifi.id
}

# Public identifiers are safe to inspect without exposing the owner identity or tokens.
output "brain_public_hostname" {
  description = "Public Second Brain hostname protected by Cloudflare Access."
  value       = cloudflare_dns_record.brain.name
}

output "brain_access_application_id" {
  description = "Cloudflare Access application ID enforcing the Second Brain owner policy."
  value       = cloudflare_zero_trust_access_application.brain.id
}
