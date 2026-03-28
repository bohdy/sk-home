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

# Track BGP instances separately so shared RouterOS routing identity stays
# reviewable and can be referenced by templates and connections by name.
variable "bgp_instances" {
  description = "BGP instance definitions managed on the MikroTik gateway."
  type = map(object({
    as            = string
    comment       = optional(string)
    disabled      = optional(bool, false)
    router_id     = optional(string)
    routing_table = optional(string, "main")
    vrf           = optional(string, "main")
  }))
  default = {}
}

# Keep reusable BGP template settings in data form so peer groups can inherit
# shared intent without repeating the same provider attributes per connection.
variable "bgp_templates" {
  description = "BGP template definitions managed on the MikroTik gateway."
  type = map(object({
    as               = string
    comment          = optional(string)
    disabled         = optional(bool, false)
    multihop         = optional(bool)
    routing_table    = optional(string, "main")
    templates        = optional(set(string), [])
    address_families = optional(string)
    add_path_out     = optional(string)
    keepalive_time   = optional(string)
    hold_time        = optional(string)
    nexthop_choice   = optional(string)
    save_to          = optional(string)
    use_bfd          = optional(bool)
    vrf              = optional(string, "main")
  }))
  default = {}
}

# Model live BGP connections with explicit nested local, remote, and output
# attributes so imported sessions can converge without hidden defaults.
variable "bgp_connections" {
  description = "BGP connection definitions managed on the MikroTik gateway."
  type = map(object({
    as               = string
    comment          = optional(string)
    disabled         = optional(bool, false)
    instance         = optional(string)
    routing_table    = optional(string, "main")
    vrf              = optional(string, "main")
    address_families = optional(string)
    connect          = optional(bool)
    multihop         = optional(bool)
    templates        = optional(set(string), [])
    local = object({
      role    = string
      address = optional(string)
      port    = optional(number)
      ttl     = optional(number)
    })
    remote = object({
      address    = string
      as         = optional(string)
      allowed_as = optional(string)
      port       = optional(number)
      ttl        = optional(number)
    })
    output = optional(object({
      affinity                       = optional(string)
      as_override                    = optional(bool, false)
      default_originate              = optional(string)
      default_prepend                = optional(number, 0)
      filter_chain                   = optional(string)
      filter_select                  = optional(string)
      keep_sent_attributes           = optional(bool, false)
      network                        = optional(string)
      no_client_to_client_reflection = optional(bool, false)
      no_early_cut                   = optional(bool, false)
      redistribute                   = optional(string)
      remove_private_as              = optional(bool, false)
    }))
  }))
  default = {}
}

# Keep routing filter rules committed in order-addressable data so BGP export
# policy remains reviewable even though RouterOS rules themselves are unnamed.
variable "routing_filter_rules" {
  description = "Routing filter rules managed on the MikroTik gateway."
  type = map(object({
    chain    = string
    comment  = optional(string)
    disabled = optional(bool, false)
    rule     = string
  }))
  default = {}
}

# Keep the provider-compatibility gateway value configurable because RouterOS
# blackhole routes do not use a next hop, but the provider still requires a
# gateway argument in the schema.
variable "blackhole_gateway_placeholder" {
  description = "Compatibility placeholder passed to the provider for blackhole routes while the provider still requires a gateway field."
  type        = string
  default     = ""
}
