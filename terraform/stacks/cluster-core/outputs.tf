# Publish the stable cluster-core outputs that downstream application stacks
# use for issuer names, storage defaults, and stack context.
output "storage_class_name" {
  description = "Default storage class name preserved from the old Pulumi stack."
  value       = var.storage_class_name
}

output "cert_issuer_prod_name" {
  description = "Production cluster issuer name used by app stacks."
  value       = "letsencrypt-prod"
}

output "cert_issuer_staging_name" {
  description = "Staging cluster issuer name used by app stacks."
  value       = "letsencrypt-staging"
}

output "stack_context" {
  description = "Non-sensitive stack metadata preserved for downstream consumers and linting."
  value       = local.common_tags
}
