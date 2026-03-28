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
  description = "Logical site name used by the routing stack."
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

# Track committed IPv4 static routes in data form so GW routing intent remains
# reviewable and future additions can reuse the same normalized structure.
variable "ipv4_static_routes" {
  description = "IPv4 static blackhole route definitions managed on the MikroTik gateway."
  type = map(object({
    dst_address   = string
    comment       = optional(string)
    routing_table = optional(string, "main")
    distance      = optional(number, 1)
    disabled      = optional(bool, false)
    blackhole     = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for route in values(var.ipv4_static_routes) : route.blackhole
    ])
    error_message = "The routing stack currently supports only IPv4 blackhole routes. Set blackhole = true for every ipv4_static_routes entry."
  }
}

# Track committed IPv6 static routes separately because the RouterOS provider
# uses a distinct Terraform resource for IPv6 route management.
variable "ipv6_static_routes" {
  description = "IPv6 static blackhole route definitions managed on the MikroTik gateway."
  type = map(object({
    dst_address   = string
    comment       = optional(string)
    routing_table = optional(string, "main")
    distance      = optional(number, 1)
    disabled      = optional(bool, false)
    blackhole     = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for route in values(var.ipv6_static_routes) : route.blackhole
    ])
    error_message = "The routing stack currently supports only IPv6 blackhole routes. Set blackhole = true for every ipv6_static_routes entry."
  }
}

# Keep the provider-compatibility gateway value configurable because RouterOS
# blackhole routes do not use a next hop, but the provider still requires a
# gateway argument in the schema.
variable "blackhole_gateway_placeholder" {
  description = "Compatibility placeholder passed to the provider for blackhole routes while the provider still requires a gateway field."
  type        = string
  default     = ""
}
