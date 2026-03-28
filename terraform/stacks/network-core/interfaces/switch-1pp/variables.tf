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
  description = "Logical site name used by the Switch 1PP interfaces stack."
  type        = string
  default     = "primary"
}

# Allow shared metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

# Keep the switch management endpoint configurable instead of embedding it in
# provider configuration.
variable "mikrotik_hosturl" {
  description = "RouterOS provider URL for the MikroTik Switch 1PP device."
  type        = string
}

# Reuse the shared RouterOS automation account until device-specific
# credentials are intentionally introduced.
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

# Describe physical Ethernet or SFP interfaces by RouterOS factory interface
# name so reviewable comments stay committed in one switch inventory.
variable "ethernet_interfaces" {
  description = "Physical Ethernet interface settings managed on Switch 1PP."
  type = map(object({
    comment  = optional(string)
    disabled = optional(bool, false)
  }))
  default = {}
}

# Keep the main switch bridge configurable in data form so VLAN filtering and
# bridge naming can evolve without editing resource logic.
variable "bridge" {
  description = "Single bridge definition managed on Switch 1PP."
  type = object({
    name           = string
    comment        = optional(string)
    vlan_filtering = optional(bool, true)
    disabled       = optional(bool, false)
  })
  default = null
}

# Model bridge ports separately so imported trunk and access behavior remains
# explicit and reviewable per physical interface.
variable "bridge_ports" {
  description = "Switch 1PP bridge-port membership and ingress behavior keyed by physical interface name."
  type = map(object({
    comment           = optional(string)
    pvid              = optional(number)
    frame_types       = optional(string)
    ingress_filtering = optional(bool)
    disabled          = optional(bool, false)
  }))
  default = {}
}

# Track bridge VLAN table entries separately from per-port settings so tagged
# and untagged membership remains easy to audit.
variable "bridge_vlans" {
  description = "Switch 1PP bridge VLAN table entries keyed by logical VLAN record name."
  type = map(object({
    comment  = optional(string)
    vlan_ids = set(string)
    tagged   = set(string)
    untagged = optional(set(string), [])
    disabled = optional(bool, false)
  }))
  default = {}
}

# Define VLAN interfaces explicitly so imported switch VLAN interfaces stay
# aligned with the committed bridge design.
variable "vlan_interfaces" {
  description = "Switch 1PP VLAN interfaces keyed by RouterOS interface name."
  type = map(object({
    comment   = optional(string)
    interface = string
    vlan_id   = number
    mtu       = optional(string)
    disabled  = optional(bool, false)
  }))
  default = {}
}
