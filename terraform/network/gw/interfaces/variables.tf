# Keep the gateway management endpoint configurable instead of embedding it in
# provider configuration.
variable "mikrotik_gw_hosturl" {
  description = "RouterOS provider URL for the MikroTik gateway device."
  type        = string
  default     = "https://gw.bohdal.name/"
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
  # Model each managed port once so bridge membership, comments, and VLAN-facing
  # access settings can be derived from the same inventory entry.
  type = map(object({
    name    = string
    comment = string
    # Null keeps the interface out of bridge port creation, which is useful for
    # routed-only or otherwise unmanaged bridge membership.
    pvid = optional(number, null)
    # Store addresses in CIDR form when the physical interface should terminate
    # a subnet directly on the router.
    ip_address = optional(string, null)
    # Optional RouterOS interface-list membership lets firewall or service
    # policy reference this port without hardcoding names elsewhere.
    iface_list = optional(string, null)
  }))
}

variable "vlans" {
  # Each map key is the VLAN ID string and each value describes which bridge
  # members should carry it tagged or expose it untagged.
  type = map(object({
    name = string
    # Tagged members should already use RouterOS interface names that exist in
    # the same declarative inventory.
    tagged   = optional(set(string), null)
    untagged = optional(set(string), null)
    //ip_address = optional(set(string), null)
    # A VLAN IP makes Terraform create a routed SVI-style interface for that
    # network on top of the shared bridge.
    ip_address = optional(string, null)
    # Optional interface-list membership is applied to the generated vlan<ID>
    # interface after creation.
    iface_list = optional(string, null)
  }))
}
