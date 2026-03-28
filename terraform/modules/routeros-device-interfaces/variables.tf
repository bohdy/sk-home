# Identify the overall project so shared metadata stays consistent across
# per-device interface roots.
variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

# Track the deployment environment without duplicating module logic.
variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
}

# Capture site-level identity for physical network resources.
variable "site_name" {
  description = "Logical site name used by the interface stack."
  type        = string
}

# Keep the Terraform stack identity explicit so tags and outputs reflect the
# device-specific root that owns the state.
variable "stack_name" {
  description = "Terraform stack name used for shared metadata tags."
  type        = string
}

# Keep the device identity explicit in outputs and normalized inventory.
variable "device_key" {
  description = "Stable device key for the managed RouterOS node."
  type        = string
}

# Carry a human-readable device label through outputs and documentation.
variable "device_name" {
  description = "Human-readable device name shown in outputs and docs."
  type        = string
}

# Capture whether the device is a gateway or switch so callers can document the
# intended blast radius of each root clearly.
variable "device_role" {
  description = "High-level role of the managed device, such as gateway or switch."
  type        = string
}

# Allow shared non-sensitive metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

# Describe physical Ethernet or SFP interfaces by RouterOS factory interface
# name so reviewable comments stay committed per device.
variable "ethernet_interfaces" {
  description = "Physical Ethernet interface settings keyed by RouterOS factory interface name."
  type = map(object({
    comment  = optional(string)
    disabled = optional(bool, false)
  }))
  default = {}
}

# Keep the device bridge configurable in data form so bridge naming and VLAN
# filtering can evolve without editing the module logic.
variable "bridge" {
  description = "Single bridge definition managed on the device, or null when the device root does not own a bridge."
  type = object({
    name           = string
    comment        = optional(string)
    vlan_filtering = optional(bool, true)
    disabled       = optional(bool, false)
  })
  default = null
}

# Model bridge ports separately so access, trunk, and hybrid behavior remains
# explicit and reviewable per physical interface.
variable "bridge_ports" {
  description = "Bridge-port membership and ingress behavior keyed by physical interface name."
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
  description = "Bridge VLAN table entries keyed by logical VLAN record name."
  type = map(object({
    comment  = optional(string)
    vlan_ids = set(string)
    tagged   = set(string)
    untagged = optional(set(string), [])
    disabled = optional(bool, false)
  }))
  default = {}
}

# Define VLAN interfaces explicitly so bridge-backed L3-facing interfaces stay
# aligned with the committed bridge design.
variable "vlan_interfaces" {
  description = "VLAN interfaces keyed by RouterOS interface name."
  type = map(object({
    comment   = optional(string)
    interface = string
    vlan_id   = number
    mtu       = optional(string)
    disabled  = optional(bool, false)
  }))
  default = {}
}

# Define 6to4 tunnel interfaces explicitly so tunnel parameters can evolve in
# the same state as the rest of the device interface topology.
variable "six_to_four_interfaces" {
  description = "6to4 tunnel interfaces keyed by RouterOS interface name."
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
