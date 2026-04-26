# Keep the gateway management endpoint configurable instead of embedding it in
# provider configuration.
variable "mikrotik_gw_hosturl" {
  description = "RouterOS provider URL for the MikroTik gateway device."
  type        = string
}

# Use a dedicated automation account for Terraform rather than the main admin
# account.
variable "mikrotik_username" {
  description = "Username for the RouterOS automation account used by Terraform."
  type        = string
}

# Keep the RouterOS password out of version control and Terraform plan output.
variable "mikrotik_password" {
  description = "Password for the RouterOS automation account used by Terraform."
  type        = string
  sensitive   = true
}

# Allow secure TLS by default while still supporting self-signed certificates
# during initial lab bootstrap.
variable "mikrotik_insecure" {
  description = "Whether the RouterOS provider should skip TLS certificate verification."
  type        = bool
  default     = true
}

variable "interfaces" {
  type = map(object({
    name           = string
    comment        = string
    pvid           = number
    tagged_vlans   = optional(set(number), null)
    untagged_vlans = optional(set(number), null)
  }))
}

variable "vlans" {
  type = map(object({
    name     = string
    tagged   = optional(set(string), null)
    untagged = optional(set(string), null)
  }))
}
