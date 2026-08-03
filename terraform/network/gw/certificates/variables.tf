variable "mikrotik_hosturl" {
  description = "RouterOS REST endpoint for the MikroTik device receiving the certificate; normal runs use HTTPS."
  type        = string
  default     = "https://gw.bohdal.name/"
}

variable "mikrotik_username" {
  description = "Dedicated RouterOS automation username sourced from Bitwarden."
  type        = string
}

variable "mikrotik_password" {
  description = "Dedicated RouterOS automation password sourced from Bitwarden."
  type        = string
  sensitive   = true
}

variable "mikrotik_insecure" {
  description = "Whether to bypass RouterOS TLS verification only while recovering an expired certificate."
  type        = bool
  default     = false
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token limited to DNS edit and zone read access for ACME DNS-01 validation."
  type        = string
  sensitive   = true
}

variable "acme_email" {
  description = "Contact address registered with Let's Encrypt for certificate-expiry and incident notices."
  type        = string
}
