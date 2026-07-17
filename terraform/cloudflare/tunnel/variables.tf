# Cloudflare account identity is configuration supplied through Bitwarden in CI
# and local environments rather than being duplicated in committed stacks.
variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the shared tunnel."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account ID."
  }
}

# The token is sensitive and must have only the tunnel-management permissions
# required by this stack.
variable "cloudflare_api_token" {
  description = "Cloudflare API token used to manage the shared tunnel."
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Stable display name for the reusable Kubernetes tunnel."
  type        = string
  default     = "sk-talos"

  validation {
    condition     = length(trimspace(var.tunnel_name)) > 0
    error_message = "tunnel_name must not be empty."
  }
}
