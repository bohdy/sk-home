# Expose the resolved stack context so the bootstrap can be validated before
# Cloudflare resources are added.
output "stack_context" {
  description = "Resolved root-module context for the identity-edge stack."
  value = {
    project_name       = var.project_name
    environment        = var.environment
    access_domain      = var.access_domain
    cloudflare_zone_id = var.cloudflare_zone_id
    common_tags        = local.common_tags
  }
}

output "tunnel_id" {
  description = "Cloudflare tunnel UUID preserved across the migration."
  value       = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
}

output "cloudflare_access_policy_id" {
  description = "Shared Access policy ID for downstream app stacks."
  value       = cloudflare_zero_trust_access_policy.allow_policy.id
}

output "cloudflare_access_group_id" {
  description = "Shared Access group ID for downstream app stacks."
  value       = cloudflare_zero_trust_access_group.allowed_users.id
}
