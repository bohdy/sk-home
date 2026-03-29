output "web_url" {
  description = "Public URL preserved for the UniFi GUI."
  value       = "https://${var.domain}"
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID for the UniFi hostname."
  value       = cloudflare_dns_record.unifi.id
}

output "stack_context" {
  description = "Non-sensitive stack metadata preserved for downstream consumers and linting."
  value = {
    project_name          = var.project_name
    environment           = var.environment
    cloudflare_account_id = var.cloudflare_account_id
  }
}
