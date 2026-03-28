# Identify the overall project this stack belongs to.
variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

# Track the target environment without duplicating stack code.
variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

# Capture site-level identity for physical network resources.
variable "site_name" {
  description = "Logical site name used by the DHCP stack."
  type        = string
  default     = "primary"
}

# Allow shared metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

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

# Define DHCP scopes in data form so pools, servers, and per-network options
# stay synchronized from one source of truth.
variable "dhcp_scopes" {
  description = "DHCP scope definitions managed on the MikroTik gateway."
  type = map(object({
    comment     = optional(string)
    interface   = string
    pool_name   = string
    range_start = string
    range_end   = string
    subnet      = string
    gateway     = string
    dns_servers = optional(list(string), [])
    domain      = optional(string)
    lease_time  = optional(string, "30m")
    add_arp     = optional(bool, false)
    option_set  = optional(string)
  }))
  default = {}
}

# Track committed static reservations separately from the broader scope map so
# device-level address intent remains easy to review and update.
variable "dhcp_reservations" {
  description = "Static DHCP reservations managed on the MikroTik gateway."
  type = map(object({
    server      = string
    address     = string
    mac_address = string
    comment     = optional(string)
  }))
  default = {}
}

# Group DHCP options into reusable option sets so scope-level vendor options can
# be attached without duplicating individual option resources.
variable "dhcp_option_sets" {
  description = "DHCP option sets and their member options managed on the gateway."
  type = map(object({
    name = string
    options = map(object({
      name    = string
      code    = number
      value   = string
      comment = optional(string)
    }))
  }))
  default = {}
}
