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
    trusted_interface_list            = optional(string, "LAN")
    wan_interface_list                = optional(string, "WAN")
    kubernetes_bgp_interface          = optional(string, "vlan20")
    kubernetes_bgp_peer_address_list  = optional(string, "sk-kubernetes-bgp-peers")
    wireguard_roadwarrior_interface   = optional(string, "wg-roadwarrior")
    wireguard_dns_source_address_list = optional(string, "sk-wireguard-roadwarrior-peers")
    wireguard_dns_service_vip         = optional(string, "10.1.30.53")
    smtp_relay_source_cidr            = optional(string, "10.1.10.250")
    smtp_relay_service_vip            = optional(string, "10.1.30.58")
    smtp_relay_port                   = optional(string, "587")
    # Keep the static NAS identity and VLAN association explicit while deriving
    # the routed source VLAN set from the authoritative VLAN inventory.
    synology_address              = optional(string, "10.1.100.10")
    synology_vlan_id              = optional(number, 100)
    synology_source_vlan_ids      = optional(set(number), [])
    internal_network_address_list = optional(string, "sk-internal-vlan-networks")
    internal_interface_list       = optional(string, "sk-internal-vlans")
    management_address_list       = optional(string, "sk-router-management-sources")
    management_ports              = optional(set(string), ["22", "443"])
    management_sources = optional(map(object({
      address = string
      comment = string
      })), {
      vlan10 = {
        address = "10.1.10.0/24"
        comment = "RouterOS management sources on VLAN 10"
      }
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
    nat_rules = optional(map(object({
      action             = string
      chain              = string
      comment            = optional(string, null)
      disabled           = optional(bool, false)
      ipsec_policy       = optional(string, null)
      src_address        = optional(string, null)
      src_address_list   = optional(string, null)
      dst_address        = optional(string, null)
      dst_address_list   = optional(string, null)
      protocol           = optional(string, null)
      src_port           = optional(string, null)
      dst_port           = optional(string, null)
      in_interface       = optional(string, null)
      in_interface_list  = optional(string, null)
      out_interface      = optional(string, null)
      out_interface_list = optional(string, null)
      to_addresses       = optional(string, null)
      to_ports           = optional(string, null)
      })), {
      legacy_disabled_media_dstnat = {
        action       = "dst-nat"
        chain        = "dstnat"
        disabled     = true
        src_address  = "10.1.102.0/24"
        dst_address  = "10.1.20.222"
        to_addresses = "10.1.30.10"
      }
      masquerade = {
        action             = "masquerade"
        chain              = "srcnat"
        comment            = "defconf: masquerade"
        ipsec_policy       = "out,none"
        out_interface_list = "WAN"
      }
      media_dstnat = {
        action            = "dst-nat"
        chain             = "dstnat"
        disabled          = false
        protocol          = "tcp"
        dst_port          = "32400"
        in_interface_list = "WAN"
        to_addresses      = "192.168.100.10"
        to_ports          = "32400"
      }
    })
    nat_rule_order = optional(list(string), [
      "legacy_disabled_media_dstnat",
      "masquerade",
      "media_dstnat",
    ])
    raw_rules = optional(map(object({
      action   = string
      chain    = string
      comment  = optional(string, null)
      disabled = optional(bool, null)
      })), {
      fasttrack_counter = {
        action  = "passthrough"
        chain   = "prerouting"
        comment = "special dummy rule to show fasttrack counters"
      }
    })
    ip_mangle_rules = optional(map(object({
      action      = string
      chain       = string
      comment     = optional(string, null)
      disabled    = optional(bool, null)
      passthrough = optional(bool, null)
      })), {
      fasttrack_counter_prerouting = {
        action  = "passthrough"
        chain   = "prerouting"
        comment = "special dummy rule to show fasttrack counters"
      }
      fasttrack_counter_forward = {
        action  = "passthrough"
        chain   = "forward"
        comment = "special dummy rule to show fasttrack counters"
      }
      fasttrack_counter_postrouting = {
        action  = "passthrough"
        chain   = "postrouting"
        comment = "special dummy rule to show fasttrack counters"
      }
    })
    ipv6_filter_rules = optional(map(object({
      action             = string
      chain              = string
      comment            = optional(string, null)
      disabled           = optional(bool, false)
      log                = optional(bool, null)
      connection_state   = optional(string, null)
      ipsec_policy       = optional(string, null)
      src_address        = optional(string, null)
      src_address_list   = optional(string, null)
      dst_address        = optional(string, null)
      dst_address_list   = optional(string, null)
      protocol           = optional(string, null)
      src_port           = optional(string, null)
      dst_port           = optional(string, null)
      in_interface       = optional(string, null)
      in_interface_list  = optional(string, null)
      out_interface      = optional(string, null)
      out_interface_list = optional(string, null)
      hop_limit          = optional(string, null)
      headers            = optional(string, null)
      reject_with        = optional(string, null)
      })), {
      custom_input_source = {
        action      = "accept"
        chain       = "input"
        comment     = "SH"
        log         = false
        src_address = "2001:718:2:40::70/128"
      }
      bgpv6_output_wireguard = {
        action        = "accept"
        chain         = "output"
        comment       = "Allow BGPv6 output to OPNsense over WG"
        dst_address   = "fd00:12::2/128"
        dst_port      = "179"
        out_interface = "wireguard1"
        protocol      = "tcp"
      }
      bgpv6_input_wireguard = {
        action       = "accept"
        chain        = "input"
        comment      = "Allow BGP IPv6 over WG"
        dst_port     = "179"
        in_interface = "wireguard1"
        protocol     = "tcp"
      }
      wireguard_ipv6_input = {
        action       = "accept"
        chain        = "input"
        in_interface = "wireguard1"
        log          = false
      }
      ipv6_input_established = {
        action           = "accept"
        chain            = "input"
        comment          = "defconf: accept established,related,untracked"
        connection_state = "established,related,untracked"
      }
      ipv6_input_drop_invalid = {
        action           = "drop"
        chain            = "input"
        comment          = "defconf: drop invalid"
        connection_state = "invalid"
      }
      ipv6_input_icmpv6 = {
        action   = "accept"
        chain    = "input"
        comment  = "defconf: accept ICMPv6"
        protocol = "icmpv6"
      }
      ipv6_input_traceroute = {
        action   = "accept"
        chain    = "input"
        comment  = "defconf: accept UDP traceroute"
        dst_port = "33434-33534"
        protocol = "udp"
      }
      ipv6_input_dhcpv6 = {
        action      = "accept"
        chain       = "input"
        comment     = "defconf: accept DHCPv6-Client prefix delegation."
        dst_port    = "546"
        protocol    = "udp"
        src_address = "fe80::/10"
      }
      ipv6_input_ike = {
        action   = "accept"
        chain    = "input"
        comment  = "defconf: accept IKE"
        dst_port = "500,4500"
        protocol = "udp"
      }
      ipv6_input_ah = {
        action   = "accept"
        chain    = "input"
        comment  = "defconf: accept ipsec AH"
        protocol = "ipsec-ah"
      }
      ipv6_input_esp = {
        action   = "accept"
        chain    = "input"
        comment  = "defconf: accept ipsec ESP"
        protocol = "ipsec-esp"
      }
      ipv6_input_ipsec = {
        action       = "accept"
        chain        = "input"
        comment      = "defconf: accept all that matches ipsec policy"
        ipsec_policy = "in,ipsec"
      }
      ipv6_input_drop_not_lan = {
        action            = "drop"
        chain             = "input"
        comment           = "defconf: drop everything else not coming from LAN"
        in_interface_list = "!LAN"
      }
      ipv6_forward_established = {
        action           = "accept"
        chain            = "forward"
        comment          = "defconf: accept established,related,untracked"
        connection_state = "established,related,untracked"
      }
      ipv6_forward_drop_invalid = {
        action           = "drop"
        chain            = "forward"
        comment          = "defconf: drop invalid"
        connection_state = "invalid"
      }
      ipv6_forward_drop_bad_src = {
        action           = "drop"
        chain            = "forward"
        comment          = "defconf: drop packets with bad src ipv6"
        src_address_list = "bad_ipv6"
      }
      ipv6_forward_drop_bad_dst = {
        action           = "drop"
        chain            = "forward"
        comment          = "defconf: drop packets with bad dst ipv6"
        dst_address_list = "bad_ipv6"
      }
      ipv6_forward_drop_hop_limit = {
        action    = "drop"
        chain     = "forward"
        comment   = "defconf: rfc4890 drop hop-limit=1"
        hop_limit = "equal:1"
        protocol  = "icmpv6"
      }
      ipv6_forward_icmpv6 = {
        action   = "accept"
        chain    = "forward"
        comment  = "defconf: accept ICMPv6"
        protocol = "icmpv6"
      }
      ipv6_forward_hip = {
        action   = "accept"
        chain    = "forward"
        comment  = "defconf: accept HIP"
        protocol = "139"
      }
      ipv6_forward_ike = {
        action   = "accept"
        chain    = "forward"
        comment  = "defconf: accept IKE"
        dst_port = "500,4500"
        protocol = "udp"
      }
      ipv6_forward_ah = {
        action   = "accept"
        chain    = "forward"
        comment  = "defconf: accept ipsec AH"
        protocol = "ipsec-ah"
      }
      ipv6_forward_esp = {
        action   = "accept"
        chain    = "forward"
        comment  = "defconf: accept ipsec ESP"
        protocol = "ipsec-esp"
      }
      ipv6_forward_ipsec = {
        action       = "accept"
        chain        = "forward"
        comment      = "defconf: accept all that matches ipsec policy"
        ipsec_policy = "in,ipsec"
      }
      ipv6_forward_drop_not_lan = {
        action            = "drop"
        chain             = "forward"
        comment           = "defconf: drop everything else not coming from LAN"
        in_interface_list = "!LAN"
      }
    })
    ipv6_filter_rule_order = optional(list(string), [
      "custom_input_source",
      "bgpv6_output_wireguard",
      "bgpv6_input_wireguard",
      "wireguard_ipv6_input",
      "ipv6_input_established",
      "ipv6_input_drop_invalid",
      "ipv6_input_icmpv6",
      "ipv6_input_traceroute",
      "ipv6_input_dhcpv6",
      "ipv6_input_ike",
      "ipv6_input_ah",
      "ipv6_input_esp",
      "ipv6_input_ipsec",
      "ipv6_input_drop_not_lan",
      "ipv6_forward_established",
      "ipv6_forward_drop_invalid",
      "ipv6_forward_drop_bad_src",
      "ipv6_forward_drop_bad_dst",
      "ipv6_forward_drop_hop_limit",
      "ipv6_forward_icmpv6",
      "ipv6_forward_hip",
      "ipv6_forward_ike",
      "ipv6_forward_ah",
      "ipv6_forward_esp",
      "ipv6_forward_ipsec",
      "ipv6_forward_drop_not_lan",
    ])
    ipv6_nat_rules = optional(map(object({
      action        = string
      chain         = string
      comment       = optional(string, null)
      disabled      = optional(bool, false)
      log           = optional(bool, null)
      src_address   = optional(string, null)
      dst_address   = optional(string, null)
      protocol      = optional(string, null)
      src_port      = optional(string, null)
      dst_port      = optional(string, null)
      in_interface  = optional(string, null)
      out_interface = optional(string, null)
      ipsec_policy  = optional(string, null)
      to_address    = optional(string, null)
      to_ports      = optional(string, null)
      })), {
      legacy_ipv6_srcnat = {
        action      = "src-nat"
        chain       = "srcnat"
        disabled    = true
        log         = false
        src_address = "2001:470:59cf::/48"
        dst_address = "2001:718:2:40::70/128"
        to_address  = "2a02:768:e900:47f:0:ffff:a15:a28e/128"
      }
    })
    ipv6_mangle_rules = optional(map(object({
      action          = string
      chain           = string
      comment         = optional(string, null)
      disabled        = optional(bool, false)
      log             = optional(bool, null)
      new_packet_mark = optional(string, null)
      passthrough     = optional(bool, null)
      })), {
      ipv6_mark = {
        action          = "mark-packet"
        chain           = "output"
        comment         = "IPv6 mark"
        log             = false
        new_packet_mark = "ipv6"
        passthrough     = true
      }
    })
    ipv6_address_lists = optional(map(object({
      list     = string
      address  = string
      comment  = optional(string, null)
      disabled = optional(bool, false)
      })), {
      unspecified = {
        list    = "bad_ipv6"
        address = "::/128"
        comment = "defconf: unspecified address"
      }
      loopback = {
        list    = "bad_ipv6"
        address = "::1/128"
        comment = "defconf: lo"
      }
      site_local = {
        list    = "bad_ipv6"
        address = "fec0::/10"
        comment = "defconf: site-local"
      }
      ipv4_mapped = {
        list    = "bad_ipv6"
        address = "::ffff:0.0.0.0/96"
        comment = "defconf: ipv4-mapped"
      }
      ipv4_compat = {
        list    = "bad_ipv6"
        address = "::/96"
        comment = "defconf: ipv4 compat"
      }
      discard_only = {
        list    = "bad_ipv6"
        address = "100::/64"
        comment = "defconf: discard only "
      }
      documentation = {
        list    = "bad_ipv6"
        address = "2001:db8::/32"
        comment = "defconf: documentation"
      }
      orchid = {
        list    = "bad_ipv6"
        address = "2001:10::/28"
        comment = "defconf: ORCHID"
      }
      sixbone = {
        list    = "bad_ipv6"
        address = "3ffe::/16"
        comment = "defconf: 6bone"
      }
    })
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
      wireguard_roadwarrior_peer_10 = {
        list    = "sk-wireguard-roadwarrior-peers"
        address = "10.1.250.10"
        comment = "WireGuard road-warrior peer 10.1.250.10"
      }
      wireguard_roadwarrior_peer_11 = {
        list    = "sk-wireguard-roadwarrior-peers"
        address = "10.1.250.11"
        comment = "WireGuard road-warrior peer 10.1.250.11"
      }
    }
    input_rules = {
      vlan10_router_management = {
        action      = "accept"
        comment     = "Allow VLAN10 router management"
        disabled    = true
        src_address = "10.1.10.0/24"
        protocol    = "tcp"
        dst_port    = "22,80,443"
      }
      vlan10_router_ping = {
        action      = "accept"
        comment     = "Allow VLAN10 router ping"
        disabled    = true
        src_address = "10.1.10.0/24"
        protocol    = "icmp"
      }
      wireguard_roadwarrior = {
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
      github_actions_runner_https = {
        action       = "accept"
        comment      = "sk-firewall/input/allow-github-actions-runner-https"
        src_address  = "10.1.20.200"
        dst_address  = "10.1.100.1"
        protocol     = "tcp"
        dst_port     = "443"
        in_interface = "vlan20"
      }
      default_accept_established = {
        action           = "accept"
        comment          = "defconf: accept established,related,untracked"
        connection_state = "established,related,untracked"
      }
      default_drop_invalid = {
        action           = "drop"
        comment          = "defconf: drop invalid"
        connection_state = "invalid"
      }
      default_accept_icmp = {
        action   = "accept"
        comment  = "defconf: accept ICMP"
        protocol = "icmp"
      }
      default_accept_loopback = {
        action      = "accept"
        comment     = "defconf: accept to local loopback (for CAPsMAN)"
        dst_address = "127.0.0.1"
      }
      default_drop_not_lan = {
        action            = "drop"
        comment           = "defconf: drop all not coming from LAN"
        in_interface_list = "!LAN"
      }
      default_accept_ipsec_esp = {
        action   = "accept"
        protocol = "ipsec-esp"
      }
      default_accept_ipsec_handshake = {
        action   = "accept"
        protocol = "udp"
        dst_port = "500,4500"
      }
    }
    forward_rules = {
      lan_to_nas = {
        action      = "accept"
        comment     = "lan-to-nas"
        disabled    = true
        dst_address = "10.1.100.10"
      }
      vlan10_to_vlan100_management = {
        action      = "accept"
        comment     = "Allow VLAN10 to VLAN100 management"
        disabled    = true
        src_address = "10.1.10.0/24"
        dst_address = "10.1.100.0/24"
        protocol    = "tcp"
        dst_port    = "22,80,443,445,5000,5001"
      }
      vlan10_to_vlan100_ping = {
        action      = "accept"
        comment     = "Allow VLAN10 to VLAN100 ping"
        disabled    = true
        src_address = "10.1.10.0/24"
        dst_address = "10.1.100.0/24"
        protocol    = "icmp"
      }
      special_dummy_fasttrack_counters = {
        # RouterOS generates this dynamic row to expose FastTrack counters.
        # Keep it adopted for identity ownership, but never move it as policy.
        action  = "passthrough"
        comment = "special dummy rule to show fasttrack counters"
      }
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
        action             = "accept"
        comment            = "sk-firewall/forward/allow-wireguard-roadwarrior-to-trusted-lan"
        src_address_list   = "sk-wireguard-roadwarrior-peers"
        dst_address        = "!10.1.30.0/24"
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
      default_accept_ipsec_in = {
        action       = "accept"
        comment      = "defconf: accept in ipsec policy"
        ipsec_policy = "in,ipsec"
      }
      default_accept_ipsec_out = {
        action       = "accept"
        comment      = "defconf: accept out ipsec policy"
        ipsec_policy = "out,ipsec"
      }
      default_fasttrack = {
        action           = "fasttrack-connection"
        comment          = "defconf: fasttrack"
        connection_state = "established,related"
      }
      default_accept_established = {
        action           = "accept"
        comment          = "defconf: accept established,related, untracked"
        connection_state = "established,related,untracked"
      }
      default_drop_invalid = {
        action           = "drop"
        comment          = "defconf: drop invalid"
        connection_state = "invalid"
      }
      default_drop_wan_not_dstnat = {
        action               = "drop"
        comment              = "defconf: drop all from WAN not DSTNATed"
        connection_state     = "new"
        connection_nat_state = "!dstnat"
        in_interface_list    = "WAN"
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

# Keep the quorum device disabled for ordinary gateway plans. The dedicated
# production-gated qdevice workflow enables it and injects only the Proxmox
# nodes' public SSH key; the private key never enters RouterOS or OpenTofu.
variable "qdevice" {
  description = "Optional RouterOS qnetd quorum-device configuration."
  type = object({
    enabled            = optional(bool, false)
    interface_name     = optional(string, "veth-qnetd")
    address            = optional(string, "10.1.100.252/24")
    gateway            = optional(string, "10.1.100.1")
    vlan_id            = optional(number, 100)
    image              = optional(string, "lpgonzalez/corosync-qnetd:1.0.0")
    root_dir           = optional(string, "usb1/qnetd/root")
    layer_dir          = optional(string, "/usb1/qnetd/layers")
    tmpdir             = optional(string, "/usb1/qnetd/tmp")
    nssdb_dir          = optional(string, "usb1/qnetd/nssdb")
    ssh_host_keys_dir  = optional(string, "usb1/qnetd/ssh-host-keys")
    ssh_authorized_dir = optional(string, "usb1/qnetd/ssh-authorized-keys")
    ssh_public_key     = optional(string, "")
  })
  default = {}

  validation {
    condition     = !var.qdevice.enabled || trimspace(var.qdevice.ssh_public_key) != ""
    error_message = "qdevice.ssh_public_key must contain a public SSH key when qdevice.enabled is true."
  }

  validation {
    # RouterOS exposes these global extraction paths with a leading slash;
    # keep them on the dedicated USB filesystem and reject traversal or empty
    # path components before they can affect other containers.
    condition = !var.qdevice.enabled || alltrue([
      for path in [var.qdevice.layer_dir, var.qdevice.tmpdir] :
      can(regex("^/usb1/[^/]+(/[^/]+)*$", path)) && !contains(split("/", path), "..")
    ])
    error_message = "qdevice.layer_dir and qdevice.tmpdir must be non-empty canonical paths below /usb1 without traversal components."
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
    name           = string
    interface_name = string
    # Tagged members should already use RouterOS interface names that exist in
    # the same declarative inventory.
    tagged   = optional(set(string), null)
    untagged = optional(set(string), null)
    //ip_address = optional(set(string), null)
    # A VLAN IP makes OpenTofu create a routed SVI-style interface for that
    # network on top of the shared bridge.
    ip_address = optional(string, null)
    # Optional interface-list membership is applied to the declared VLAN
    # interface after creation.
    iface_list = optional(string, null)
  }))
}
