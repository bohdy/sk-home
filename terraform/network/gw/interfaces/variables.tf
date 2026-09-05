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

# Keep all non-secret firewall decisions in one structured object so the
# intended exceptions and the default-deny boundaries can be reviewed together.
variable "firewall_policy" {
  description = "Non-secret RouterOS input and forward firewall policy."
  type = object({
    trusted_interface_list             = optional(string, "LAN")
    wan_interface_list                 = optional(string, "WAN")
    kubernetes_bgp_interface           = optional(string, "vlan20")
    kubernetes_bgp_peer_address_list   = optional(string, "sk-kubernetes-bgp-peers")
    wireguard_roadwarrior_interface    = optional(string, "wg-roadwarrior")
    wireguard_roadwarrior_address_list = optional(string, "sk-wireguard-roadwarrior-peers")
    wireguard_roadwarrior_peer_addresses = optional(set(string), [
      "10.1.250.10",
      "10.1.250.11",
    ])
    wireguard_dns_service_vip = optional(string, "10.1.30.53")
    smtp_relay_source_cidr    = optional(string, "10.1.10.250")
    smtp_relay_service_vip    = optional(string, "10.1.30.58")
    smtp_relay_port           = optional(string, "587")
    management_address_list   = optional(string, "sk-router-management-sources")
    management_ports          = optional(set(string), ["22", "443"])
    management_sources = optional(map(object({
      address = string
      comment = string
      })), {
      vlan100 = {
        address = "10.1.100.0/24"
        comment = "RouterOS management sources on VLAN 100"
      }
    })
    snmp_source_cidr = optional(string, "10.0.0.0/8")
    address_lists = map(object({
      list    = string
      address = string
      comment = optional(string, null)
    }))
    input_rules = map(object({
      action               = string
      comment              = optional(string, null)
      disabled             = optional(bool, false)
      connection_state     = optional(string, null)
      connection_nat_state = optional(string, null)
      ipsec_policy         = optional(string, null)
      src_address          = optional(string, null)
      src_address_list     = optional(string, null)
      dst_address          = optional(string, null)
      dst_address_list     = optional(string, null)
      protocol             = optional(string, null)
      src_port             = optional(string, null)
      dst_port             = optional(string, null)
      in_interface         = optional(string, null)
      in_interface_list    = optional(string, null)
      out_interface        = optional(string, null)
      out_interface_list   = optional(string, null)
    }))
    forward_rules = map(object({
      action               = string
      comment              = optional(string, null)
      disabled             = optional(bool, false)
      connection_state     = optional(string, null)
      connection_nat_state = optional(string, null)
      ipsec_policy         = optional(string, null)
      src_address          = optional(string, null)
      src_address_list     = optional(string, null)
      dst_address          = optional(string, null)
      dst_address_list     = optional(string, null)
      protocol             = optional(string, null)
      src_port             = optional(string, null)
      dst_port             = optional(string, null)
      in_interface         = optional(string, null)
      in_interface_list    = optional(string, null)
      out_interface        = optional(string, null)
      out_interface_list   = optional(string, null)
    }))
    forward_management_rules = optional(map(object({
      comment            = string
      disabled           = optional(bool, false)
      src_address        = optional(string, null)
      src_address_list   = optional(string, null)
      dst_address        = optional(string, null)
      dst_address_list   = optional(string, null)
      protocol           = optional(string, null)
      src_port           = optional(string, null)
      dst_port           = optional(string, null)
      in_interface_list  = optional(string, null)
      out_interface_list = optional(string, null)
    })), {})
  })
  default = {
    # The public VPN endpoint is already used by the live KNOWN WAN rule; keep
    # its address-list ownership declarative without changing its value.
    address_lists = {
      known_wan = {
        list    = "ACCD"
        address = "44.237.169.3"
        comment = "VPN-WEST-02"
      }
    }
    input_rules = {
      github_actions_runner_https = {
        # Keep the trusted self-hosted runner's recovery path narrow: it may
        # reach only the gateway HTTPS API, not arbitrary router services or
        # forwarded hosts on the other VLANs.
        action       = "accept"
        comment      = "sk-firewall/input/allow-github-actions-runner-https"
        src_address  = "10.1.20.200"
        dst_address  = "10.1.100.1"
        in_interface = "vlan20"
        protocol     = "tcp"
        dst_port     = "443"
      }
      wireguard_roadwarrior = {
        # Reuse this adopted state address for the verified WAN handshake, so
        # the unsafe broad input rule is narrowed without a destroy.
        action            = "accept"
        comment           = "wireguard"
        protocol          = "udp"
        dst_port          = "51820"
        in_interface_list = "WAN"
      }
      ssh_lan = {
        action            = "accept"
        comment           = "SSH LAN IN"
        disabled          = true
        protocol          = "tcp"
        dst_port          = "22"
        in_interface_list = "LAN"
      }
      kubernetes_snmp = {
        action      = "accept"
        comment     = "LAN k3s"
        disabled    = true
        src_address = "10.42.0.0/16"
        protocol    = "udp"
        dst_port    = "161"
      }
      snmp_lan = {
        action            = "accept"
        comment           = "SNMP LAN IN"
        disabled          = true
        protocol          = "udp"
        dst_port          = "161"
        in_interface_list = "LAN"
      }
      wireguard_handshake = {
        action   = "accept"
        comment  = "Allow WireGuard roadwarrior"
        disabled = true
        protocol = "udp"
        dst_port = "51820"
      }
      wireguard_site_to_site_handshake = {
        action            = "accept"
        comment           = "Allow WireGuard site-to-site handshake"
        protocol          = "udp"
        dst_port          = "51280"
        in_interface_list = "WAN"
      }
    }
    forward_rules = {
      site_to_site = {
        action      = "accept"
        comment     = "sk-firewall/forward/allow-site-to-site"
        src_address = "10.1.0.0/16"
        dst_address = "10.2.0.0/16"
      }
      known_wan = {
        action            = "accept"
        comment           = "KNOWN WAN"
        src_address_list  = "ACCD"
        in_interface_list = "WAN"
      }
      wireguard_roadwarrior_to_trusted_lan = {
        action  = "accept"
        comment = "sk-firewall/forward/allow-wireguard-roadwarrior-to-trusted-lan"
        # Match only the two verified active peer addresses through a managed
        # address list so the provider never serializes a malformed range.
        src_address_list   = "sk-wireguard-roadwarrior-peers"
        in_interface       = "wg-roadwarrior"
        out_interface_list = "LAN"
      }
      wireguard_site_to_site_to_trusted_lan = {
        action             = "accept"
        comment            = "sk-firewall/forward/allow-wireguard-site-to-site-to-trusted-lan"
        src_address        = "10.2.0.0/16"
        in_interface       = "wireguard1"
        out_interface_list = "LAN"
      }
    }
  }
}

# WireGuard interface identity and peer metadata are non-secret desired state.
# Existing private keys and preshared keys stay in encrypted OpenTofu state and
# are deliberately ignored during adoption so this migration never prints or
# regenerates key material.
variable "wireguard_interfaces" {
  description = "Verified WireGuard interfaces to adopt on the gateway."
  type = map(object({
    name        = string
    listen_port = number
    mtu         = optional(string, null)
    comment     = optional(string, null)
  }))
  default = {
    roadwarrior = {
      name        = "wg-roadwarrior"
      listen_port = 51820
      mtu         = "1420"
    }
    site_to_site = {
      name        = "wireguard1"
      listen_port = 51280
      mtu         = "1420"
    }
  }
}

variable "wireguard_peers" {
  description = "Verified WireGuard peer public configuration to adopt."
  type = map(object({
    interface            = string
    public_key           = string
    allowed_address      = list(string)
    endpoint_address     = optional(string, null)
    endpoint_port        = optional(string, null)
    persistent_keepalive = optional(string, null)
    disabled             = optional(bool, false)
    comment              = optional(string, null)
  }))
  default = {
    site_to_site_sh = {
      interface        = "wireguard1"
      public_key       = "1nxcJU+oaBJ2Vw4gXjx7ZBFmTdMJTPlEkLavhMsHmGo="
      allowed_address  = ["169.254.0.2/32", "fd00:12::2/128", "10.2.0.0/16", "2001:718:2:d7::/64"]
      endpoint_address = "2001:718:2:40::70"
      endpoint_port    = "51820"
      comment          = "SH"
    }
    site_to_site_ck = {
      interface            = "wireguard1"
      public_key           = "gL+kVkdg4SuMhz5GXINNC7N4O7ITyiDx5BcCoBCiTgI="
      allowed_address      = ["169.254.0.0/24", "fd00:10::/64"]
      endpoint_address     = "2001:470:6e:969::2"
      endpoint_port        = "13231"
      persistent_keepalive = "5s"
      disabled             = true
      comment              = "CK"
    }
    roadwarrior_viktor = {
      interface        = "wg-roadwarrior"
      public_key       = "Irpx45OP/VgU7ua+tfHa+mweEvq4GWmPy+F2A9+9ZkQ="
      allowed_address  = ["10.1.250.10/32"]
      endpoint_address = ""
      endpoint_port    = "0"
      comment          = "Viktor MacBookPro"
    }
    roadwarrior_ipad = {
      interface        = "wg-roadwarrior"
      public_key       = "//NZ0x1Ni9H4lWwOD9vbK/hJY6hcQW8Jzyy1WaFSono="
      allowed_address  = ["10.1.250.11/32"]
      endpoint_address = ""
      endpoint_port    = "0"
      comment          = "ipad"
    }
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
