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

# Keep the shared managed VLAN catalog symbolic so per-device roots can refer
# to stable VLAN keys instead of repeating RouterOS VLAN IDs and interface
# names in multiple data structures.
variable "vlan_catalog" {
  description = "Managed VLAN catalog keyed by stable VLAN key."
  type = map(object({
    vlan_id        = number
    interface_name = string
    comment        = string
  }))
  default = {}
}

# Model bridge ports in one structure so ingress policy and explicit tagged or
# untagged VLAN membership stay reviewable per physical interface.
variable "bridge_ports" {
  description = "Bridge-port membership and ingress behavior keyed by physical interface name."
  type = map(object({
    comment           = optional(string)
    pvid              = optional(number)
    pvid_vlan         = optional(string)
    tagged_vlans      = optional(set(string), [])
    untagged_vlans    = optional(set(string), [])
    frame_types       = optional(string)
    ingress_filtering = optional(bool)
    disabled          = optional(bool, false)
  }))
  default = {}
}

# Control which shared VLAN catalog entries receive bridge VLAN table rows
# on this device so each root commits only the VLANs it actually carries.
variable "bridge_vlan_keys" {
  description = "Shared VLAN catalog keys that should have bridge VLAN table entries on this device."
  type        = set(string)
  default     = []
}

# Keep per-device VLAN behavior separate from the shared catalog so interface
# ownership can differ without redefining VLAN IDs or canonical comments.
variable "device_vlans" {
  description = "Per-device VLAN behavior keyed by shared VLAN catalog key."
  type = map(object({
    create_vlan_interface = optional(bool, false)
    vlan_interface_parent = optional(string)
    vlan_interface_mtu    = optional(string)
    disabled              = optional(bool, false)
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

# Keep IPv4 interface addresses in committed data so L3 gateway or switch
# interface identities are managed alongside the L2 interface topology.
variable "ipv4_interface_addresses" {
  description = "IPv4 interface addresses keyed by a stable logical address key."
  type = map(object({
    interface = string
    address   = string
    comment   = optional(string)
    disabled  = optional(bool, false)
    vrf       = optional(string)
  }))
  default = {}
}

# Keep IPv6 interface addresses in committed data so dual-stack interface
# ownership is reviewable and importable through the same per-device root.
variable "ipv6_interface_addresses" {
  description = "IPv6 interface addresses keyed by a stable logical address key."
  type = map(object({
    interface       = string
    address         = string
    comment         = optional(string)
    disabled        = optional(bool, false)
    advertise       = optional(bool)
    auto_link_local = optional(bool)
    eui_64          = optional(bool)
    from_pool       = optional(string)
    no_dad          = optional(bool)
  }))
  default = {}
}
