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
  description = "Logical site name used by the interfaces stack."
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

# Keep the first switch management endpoint configurable instead of embedding it
# in provider configuration.
variable "mikrotik_switch_1pp_hosturl" {
  description = "RouterOS provider URL for the MikroTik Switch 1PP device."
  type        = string
}

# Keep the second switch management endpoint configurable instead of embedding
# it in provider configuration.
variable "mikrotik_switch_1np_hosturl" {
  description = "RouterOS provider URL for the MikroTik Switch 1NP device."
  type        = string
}

# Use one dedicated automation account shape across the three devices until
# device-specific credentials are intentionally introduced.
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

# Describe physical Ethernet or SFP interfaces by device and factory interface
# name so reviewable comments stay committed in one shared inventory.
variable "ethernet_interfaces" {
  description = "Physical Ethernet interface settings managed on the MikroTik devices."
  type = map(map(object({
    comment  = optional(string)
    disabled = optional(bool, false)
  })))
  default = {}

  validation {
    condition = alltrue([
      for device_name in keys(var.ethernet_interfaces) :
      contains(["gw", "switch_1pp", "switch_1np"], device_name)
    ])
    error_message = "ethernet_interfaces supports only the device keys gw, switch_1pp, and switch_1np."
  }
}

# Keep the main gateway bridge configurable in data form so VLAN filtering and
# bridge naming can evolve without editing resource logic.
variable "gw_bridge" {
  description = "Single bridge definition managed on the gateway."
  type = object({
    name           = string
    comment        = optional(string)
    vlan_filtering = optional(bool, true)
    disabled       = optional(bool, false)
  })
}

# Model bridge ports separately so access, trunk, and hybrid behavior remains
# explicit and reviewable per gateway interface.
variable "gw_bridge_ports" {
  description = "Gateway bridge-port membership and ingress behavior keyed by physical interface name."
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
variable "gw_bridge_vlans" {
  description = "Gateway bridge VLAN table entries keyed by logical VLAN record name."
  type = map(object({
    comment  = optional(string)
    vlan_ids = set(string)
    tagged   = set(string)
    untagged = optional(set(string), [])
    disabled = optional(bool, false)
  }))
  default = {}
}

# Define VLAN interfaces explicitly so the gateway bridge carries a committed
# L3-facing interface inventory alongside its L2 VLAN table.
variable "gw_vlan_interfaces" {
  description = "Gateway VLAN interfaces keyed by RouterOS interface name."
  type = map(object({
    comment   = optional(string)
    interface = string
    vlan_id   = number
    mtu       = optional(string)
    disabled  = optional(bool, false)
  }))
  default = {}
}

# Define 6to4 tunnel interfaces explicitly so tunnel parameters live in the
# same stack as the rest of the gateway interface topology.
variable "gw_6to4_interfaces" {
  description = "Gateway 6to4 tunnel interfaces keyed by RouterOS interface name."
  type = map(object({
    comment        = optional(string)
    clamp_tcp_mss  = optional(bool, false)
    local_address  = string
    mtu            = optional(string, "auto")
    remote_address = string
    disabled       = optional(bool, false)
  }))
  default = {}
}
