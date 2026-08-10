# Keep the gateway management endpoint configurable instead of embedding it in
# provider configuration.
variable "mikrotik_gw_hosturl" {
  description = "RouterOS provider URL for the MikroTik gateway device."
  type        = string
  default     = "https://gw.bohdal.name/"
}

# Use a dedicated automation account for OpenTofu rather than the main admin
# account.
variable "mikrotik_username" {
  description = "Username for the RouterOS automation account used by OpenTofu."
  type        = string
}

# Keep the RouterOS password out of version control and OpenTofu plan output.
variable "mikrotik_password" {
  description = "Password for the RouterOS automation account used by OpenTofu."
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

variable "kubernetes_bgp" {
  # Keep the Kubernetes peering policy together so RouterOS accepts only the
  # dedicated service VIP routes expected from the Talos nodes.
  description = "BGP settings for peering the MikroTik gateway with Kubernetes nodes."
  type = object({
    enabled                  = optional(bool, true)
    local_asn                = optional(number, 65001)
    remote_asn               = optional(number, 65001)
    local_address            = optional(string, "10.1.20.1")
    service_vip_cidr         = optional(string, "10.1.30.0/24")
    service_vip_address_list = optional(string, "sk-kubernetes-service-vips")
    input_filter_chain       = optional(string, "sk-kubernetes-bgp-in")
    nodes = optional(map(object({
      address = string
      comment = string
      })), {
      cp1 = {
        address = "10.1.20.41"
        comment = "sk-talos-cp-1"
      }
      cp2 = {
        address = "10.1.20.42"
        comment = "sk-talos-cp-2"
      }
      cp3 = {
        address = "10.1.20.43"
        comment = "sk-talos-cp-3"
      }
      worker1 = {
        address = "10.1.20.44"
        comment = "sk-talos-worker-1"
      }
      worker2 = {
        address = "10.1.20.45"
        comment = "sk-talos-worker-2"
      }
      worker3 = {
        address = "10.1.20.46"
        comment = "sk-talos-worker-3"
      }
    })
  })
  default = {}
}

variable "kubernetes_bgp_tcp_md5_key" {
  # RouterOS and Cilium both use this shared RFC 2385 key for the BGP sessions;
  # source it from Bitwarden and never commit the plaintext value.
  description = "Shared TCP MD5 key used to authenticate Kubernetes BGP sessions."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.kubernetes_bgp_tcp_md5_key) > 0
    error_message = "The Kubernetes BGP TCP MD5 key must be provided from the secret store."
  }
}

# Keep SNMP community and user identities sensitive because RouterOS represents
# both as the community `name`, and v2c uses that value as its shared secret.
variable "snmp_v2_community" {
  description = "Read-only SNMPv2c community used by compatibility collectors."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.snmp_v2_community) >= 8
    error_message = "The SNMPv2c community must contain at least eight characters."
  }
}

variable "snmp_v3_username" {
  description = "Security name for the read-only SNMPv3 collector identity."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.snmp_v3_username) >= 8
    error_message = "The SNMPv3 username must contain at least eight characters."
  }
}

variable "snmp_v3_auth_password" {
  description = "Authentication password for the SNMPv3 collector identity."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.snmp_v3_auth_password) >= 8
    error_message = "The SNMPv3 authentication password must contain at least eight characters."
  }
}

variable "snmp_v3_priv_password" {
  description = "Privacy password for the SNMPv3 collector identity."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.snmp_v3_priv_password) >= 8
    error_message = "The SNMPv3 privacy password must contain at least eight characters."
  }
}

# Keep the packet policy in one non-secret object so rule matchers, interface
# lists, and live-inventory-derived exceptions remain reviewable together.
variable "firewall_policy" {
  description = "Non-secret RouterOS input and forward firewall policy."
  type = object({
    trusted_interface_list   = optional(string, "LAN")
    wan_interface_list       = optional(string, "WAN")
    kubernetes_bgp_interface = optional(string, "vlan20")
    management_source_cidr   = optional(string, "10.1.100.0/24")
    management_ports         = optional(set(string), ["443"])
    snmp_source_cidr         = optional(string, "10.0.0.0/8")
    service_vip_address_list = optional(string, "sk-kubernetes-service-vips")
    kubernetes_node_addresses = optional(set(string), [
      "10.1.20.41",
      "10.1.20.42",
      "10.1.20.43",
      "10.1.20.44",
      "10.1.20.45",
      "10.1.20.46",
    ])
    wireguard = optional(object({
      # Keep remote-access rules disabled until the read-only inventory confirms
      # the live interface, tunnel CIDR, and listen port.
      enabled        = optional(bool, false)
      interface_name = optional(string)
      source_cidr    = optional(string)
      listen_port    = optional(string)
    }), {})
    # These entries are intentionally empty until the live baseline identifies
    # an approved inter-VLAN management path. No broad management exception is
    # safe to infer from the existing VLAN names alone.
    forward_management_rules = optional(map(object({
      src_address        = optional(string)
      src_address_list   = optional(string)
      dst_address        = optional(string)
      dst_address_list   = optional(string)
      protocol           = optional(string)
      src_port           = optional(string)
      dst_port           = optional(string)
      in_interface_list  = optional(string)
      out_interface_list = optional(string)
      comment            = string
    })), {})
  })
  default = {}

  validation {
    condition = !var.firewall_policy.wireguard.enabled || (
      var.firewall_policy.wireguard.interface_name != null &&
      var.firewall_policy.wireguard.source_cidr != null &&
      var.firewall_policy.wireguard.listen_port != null
    )
    error_message = "Enabled WireGuard firewall policy requires the verified interface name, tunnel CIDR, and listen port."
  }
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
    # A VLAN IP makes OpenTofu create a routed SVI-style interface for that
    # network on top of the shared bridge.
    ip_address = optional(string, null)
    # Optional interface-list membership is applied to the generated vlan<ID>
    # interface after creation.
    iface_list = optional(string, null)
  }))
}
