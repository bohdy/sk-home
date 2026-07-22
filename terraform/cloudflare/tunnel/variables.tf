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

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns the public Grafana hostname."
  type        = string
  default     = "48fce2129073417a753d224107dcefa1"

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_zone_id))
    error_message = "cloudflare_zone_id must be a 32-character hexadecimal Cloudflare zone ID."
  }
}

variable "google_identity_provider_id" {
  description = "Cloudflare Access identity provider ID for the existing Google login method."
  type        = string
  default     = "d7e5b598-e52d-4699-a41f-44e382917fb2"

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.google_identity_provider_id))
    error_message = "google_identity_provider_id must be a Cloudflare UUID."
  }
}

variable "grafana_hostname" {
  description = "Canonical hostname shared by LAN split DNS, public DNS, Grafana, and Cloudflare Access."
  type        = string
  default     = "grafana.bohdal.name"

  validation {
    condition     = var.grafana_hostname == lower(trimspace(var.grafana_hostname)) && can(regex("^[a-z0-9.-]+$", var.grafana_hostname))
    error_message = "grafana_hostname must be a normalized lowercase DNS hostname."
  }
}

variable "grafana_origin_service" {
  description = "In-cluster HTTPS origin reached by the shared cloudflared connectors."
  type        = string
  default     = "https://metrics-grafana.observability.svc.cluster.local:443"

  validation {
    condition     = startswith(var.grafana_origin_service, "https://")
    error_message = "grafana_origin_service must use HTTPS."
  }
}

variable "grafana_access_email" {
  description = "Exact Gmail identity allowed by the Grafana Cloudflare Access policy."
  type        = string
  sensitive   = true

  validation {
    condition     = var.grafana_access_email == lower(trimspace(var.grafana_access_email)) && can(regex("^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@gmail\\.com$", var.grafana_access_email))
    error_message = "grafana_access_email must be one normalized @gmail.com address."
  }
}
