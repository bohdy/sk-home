# Read the live chains so ownership and the initial adoption order are based on
# the current RouterOS identities instead of volatile numeric positions.
data "routeros_ip_firewall" "input_rules" {
  provider = routeros.gw

  rules {
    filter = {
      chain = "input"
    }
  }
}

data "routeros_ip_firewall" "forward_rules" {
  provider = routeros.gw

  rules {
    filter = {
      chain = "forward"
    }
  }
}

data "routeros_ip_firewall" "nat_rules" {
  provider = routeros.gw

  nat {}
}

data "routeros_ip_firewall" "mangle_rules" {
  provider = routeros.gw

  mangle {}
}

data "routeros_ipv6_firewall" "rules" {
  provider = routeros.gw

  rules {}
  nat {}
  mangle {}
}

# Bridge filtering is a separate RouterOS table. The live baseline has no rows,
# so fail closed if a future bridge rule appears before a reviewed resource is
# added to this stack.
data "routeros_interface_bridge_filter" "rules" {
  provider = routeros.gw
}

locals {
  # A live rule is owned only when its RouterOS identity belongs to a managed
  # resource in state. Matching a comment is deliberately insufficient: an
  # unimported duplicate or exception must fail the ownership guard.
  managed_input_rule_ids = concat(
    [for rule in values(routeros_ip_firewall_filter.adopted_input) : rule.id],
    compact([
      try(routeros_ip_firewall_filter.input_accept_established.id, null),
      try(routeros_ip_firewall_filter.input_drop_invalid.id, null),
      try(routeros_ip_firewall_filter.input_allow_icmp_trusted.id, null),
      try(routeros_ip_firewall_filter.input_allow_loopback.id, null),
      try(routeros_ip_firewall_filter.input_allow_dhcp.id, null),
      try(routeros_ip_firewall_filter.input_allow_dns_udp.id, null),
      try(routeros_ip_firewall_filter.input_allow_dns_tcp.id, null),
      try(routeros_ip_firewall_filter.input_allow_ipsec_esp.id, null),
      try(routeros_ip_firewall_filter.input_allow_ipsec_handshake.id, null),
      try(routeros_ip_firewall_filter.input_allow_kubernetes_bgp[0].id, null),
      try(routeros_ip_firewall_filter.input_allow_snmp_monitoring.id, null),
      try(routeros_ip_firewall_filter.input_allow_management.id, null),
      try(routeros_ip_firewall_filter.input_drop_unmatched.id, null),
    ]),
  )
  managed_forward_rule_ids = concat(
    [for rule in values(routeros_ip_firewall_filter.adopted_forward) : rule.id],
    compact([
      try(routeros_ip_firewall_filter.forward_fasttrack_established.id, null),
      try(routeros_ip_firewall_filter.forward_accept_established.id, null),
      try(routeros_ip_firewall_filter.forward_drop_invalid.id, null),
      try(routeros_ip_firewall_filter.forward_allow_ipsec_in.id, null),
      try(routeros_ip_firewall_filter.forward_allow_ipsec_out.id, null),
      try(routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan.id, null),
      try(routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips[0].id, null),
      try(routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_udp.id, null),
      try(routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_tcp.id, null),
      try(routeros_ip_firewall_filter.forward_allow_smtp_relay_from_printer.id, null),
      try(routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id, null),
      try(routeros_ip_firewall_filter.allow_synology_snmp_responses.id, null),
      try(routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id, null),
      try(routeros_ip_firewall_filter.allow_unifi_snmp_responses.id, null),
      try(routeros_ip_firewall_filter.allow_kubernetes_proxmox.id, null),
      try(routeros_ip_firewall_filter.allow_kubernetes_dell.id, null),
      try(routeros_ip_firewall_filter.forward_allow_wan_dstnat.id, null),
      try(routeros_ip_firewall_filter.forward_drop_inter_vlan.id, null),
      try(routeros_ip_firewall_filter.forward_drop_wan_inbound.id, null),
      try(routeros_ip_firewall_filter.forward_drop_unmatched.id, null),
    ]),
    [for rule in values(routeros_ip_firewall_filter.forward_allow_synology_from_vlans) : rule.id],
    [for rule in values(routeros_ip_firewall_filter.forward_management) : rule.id],
  )

  # NAT has a separate RouterOS table and therefore needs its own strict
  # identity check; importing filter rules alone must not hide an unmanaged
  # masquerade or destination-NAT exception.
  managed_nat_rule_ids = [for rule in values(routeros_ip_firewall_nat.adopted) : rule.id]

  input_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.input_rules.rules : rule.id
    if !contains(local.managed_input_rule_ids, rule.id)
  ]
  forward_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.forward_rules.rules : rule.id
    if !contains(local.managed_forward_rule_ids, rule.id)
  ]
  nat_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.nat_rules.nat : rule.id
    if !contains(local.managed_nat_rule_ids, rule.id)
  ]
  managed_ipv6_filter_rule_ids = [for rule in values(routeros_ipv6_firewall_filter.adopted) : rule.id]
  ipv6_filter_unmanaged_rule_ids = [
    for rule in data.routeros_ipv6_firewall.rules.rules : rule.id
    if !contains(local.managed_ipv6_filter_rule_ids, rule.id)
  ]

  # The Kubernetes BGP node map is the single source of truth for the exact
  # peer addresses allowed to establish TCP/179 sessions.
  kubernetes_bgp_addresses = var.kubernetes_bgp.enabled ? {
    for address in distinct([
      for node in values(var.kubernetes_bgp.nodes) : node.address
    ]) : replace(address, ".", "_") => address
  } : {}

  # Keep the first policy cutover limited to the verified management VLAN. A
  # future remote-management exception must add an explicit address-list entry.
  management_sources = var.firewall_policy.management_sources

  # VLAN 100 is the Synology layer-2 segment. Derive every other routed VLAN
  # from the authoritative inventory unless an operator deliberately supplies
  # a narrower reviewed source set.
  synology_source_vlan_ids = length(var.firewall_policy.synology_source_vlan_ids) > 0 ? tolist(var.firewall_policy.synology_source_vlan_ids) : [
    for vlan_id, vlan in var.vlans : tonumber(vlan_id)
    if tonumber(vlan_id) != var.firewall_policy.synology_vlan_id && vlan.ip_address != null
  ]
  synology_routed_vlans = {
    for vlan_id in local.synology_source_vlan_ids : tostring(vlan_id) => {
      source_subnet = try(cidrsubnet(var.vlans[tostring(vlan_id)].ip_address, 0, 0), null)
      in_interface  = try(var.vlans[tostring(vlan_id)].interface_name, null)
    }
  }

  # All gateway VLANs need access to the Kubernetes service VIPs used by
  # internal DNS and applications. This explicit address list avoids adding
  # camera or AP VLANs to the broader LAN interface list.
  internal_networks = {
    for vlan_id, vlan in var.vlans : tostring(vlan_id) => {
      address = cidrsubnet(vlan.ip_address, 0, 0)
      comment = "Internal VLAN ${vlan_id} network"
    } if vlan.ip_address != null
  }

  active_input_adoption_keys = [
    "github_actions_runner_https",
    "wireguard_roadwarrior",
    "wireguard_site_to_site_handshake",
  ]
  active_forward_adoption_keys = [
    "site_to_site",
    "known_wan",
    "wireguard_roadwarrior_to_trusted_lan",
    "wireguard_site_to_site_to_trusted_lan",
  ]

  # RouterOS creates this FastTrack counter row dynamically. It is represented
  # in state for complete identity ownership, but must not be passed to the
  # provider's move endpoint as if it were a normal policy rule.
  dynamic_forward_adoption_keys = [
    "special_dummy_fasttrack_counters",
  ]

  nat_rule_order         = var.firewall_policy.nat_rule_order
  ipv6_filter_rule_order = var.firewall_policy.ipv6_filter_rule_order

}

# Preserve the existing public VPN endpoint address-list entry while bringing
# its ownership into the same policy file as the firewall rules.
resource "routeros_ip_firewall_addr_list" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.address_lists

  list    = each.value.list
  address = each.value.address
  comment = each.value.comment
}

# Keep the internal service boundary explicit instead of broadening the LAN
# interface list. This allows routed VLANs 101 and 102 to use Kubernetes VIPs
# while their other inter-VLAN and WAN traffic remains denied by policy.
resource "routeros_ip_firewall_addr_list" "internal_networks" {
  provider = routeros.gw
  for_each = local.internal_networks

  list    = var.firewall_policy.internal_network_address_list
  address = each.value.address
  comment = each.value.comment
}

# Restrict BGP input to the exact six Kubernetes nodes declared by the BGP
# inventory. The list is separate from the service-VIP list used by routing.
resource "routeros_ip_firewall_addr_list" "kubernetes_bgp_peers" {
  provider = routeros.gw
  for_each = local.kubernetes_bgp_addresses

  list    = var.firewall_policy.kubernetes_bgp_peer_address_list
  address = each.value
  comment = "Kubernetes BGP peer ${each.value}"
}

# The management list is intentionally narrow and non-secret. Its entries are
# the only source addresses permitted to use the router management ports.
resource "routeros_ip_firewall_addr_list" "management_sources" {
  provider = routeros.gw
  for_each = local.management_sources

  list    = var.firewall_policy.management_address_list
  address = each.value.address
  comment = each.value.comment
}

# Map-driven adoption keeps the current resource addresses stable while the
# policy transitions from the live baseline to the explicit ordered contract.
resource "routeros_ip_firewall_filter" "adopted_input" {
  provider = routeros.gw
  for_each = var.firewall_policy.input_rules

  action               = each.value.action
  chain                = "input"
  comment              = each.value.comment
  disabled             = each.value.disabled
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
  ipsec_policy         = each.value.ipsec_policy
  src_address          = each.value.src_address
  src_address_list     = each.value.src_address_list
  dst_address          = each.value.dst_address
  dst_address_list     = each.value.dst_address_list
  protocol             = each.value.protocol
  src_port             = each.value.src_port
  dst_port             = each.value.dst_port
  in_interface         = each.value.in_interface
  in_interface_list    = each.value.in_interface_list
  out_interface        = each.value.out_interface
  out_interface_list   = each.value.out_interface_list
}

resource "routeros_ip_firewall_filter" "adopted_forward" {
  provider = routeros.gw
  for_each = var.firewall_policy.forward_rules

  action               = each.value.action
  chain                = "forward"
  comment              = each.value.comment
  disabled             = each.value.disabled
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
  ipsec_policy         = each.value.ipsec_policy
  src_address          = each.value.src_address
  src_address_list     = each.value.src_address_list
  dst_address          = each.value.dst_address
  dst_address_list     = each.value.dst_address_list
  protocol             = each.value.protocol
  src_port             = each.value.src_port
  dst_port             = each.value.dst_port
  in_interface         = each.value.in_interface
  in_interface_list    = each.value.in_interface_list
  out_interface        = each.value.out_interface
  out_interface_list   = each.value.out_interface_list

  depends_on = [routeros_ip_firewall_addr_list.adopted]
}

# Adopt every live NAT row with the same complete attribute model used for
# filter rules. The disabled legacy destination-NAT row remains represented so
# it cannot become an unreviewed exception later.
resource "routeros_ip_firewall_nat" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.nat_rules

  action             = each.value.action
  chain              = each.value.chain
  comment            = each.value.comment
  disabled           = each.value.disabled
  ipsec_policy       = each.value.ipsec_policy
  src_address        = each.value.src_address
  src_address_list   = each.value.src_address_list
  dst_address        = each.value.dst_address
  dst_address_list   = each.value.dst_address_list
  protocol           = each.value.protocol
  src_port           = each.value.src_port
  dst_port           = each.value.dst_port
  in_interface       = each.value.in_interface
  in_interface_list  = each.value.in_interface_list
  out_interface      = each.value.out_interface
  out_interface_list = each.value.out_interface_list
  to_addresses       = each.value.to_addresses
  to_ports           = each.value.to_ports
}

# RouterOS creates the raw and IP mangle FastTrack counter rows dynamically.
# Keep their identities in state so the inventory has no unowned firewall
# table entries, while avoiding move or policy mutations for generated rows.
resource "routeros_ip_firewall_raw" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.raw_rules

  action   = each.value.action
  chain    = each.value.chain
  comment  = each.value.comment
  disabled = each.value.disabled

  # These are RouterOS-generated FastTrack counter rows; provider defaults
  # must never turn an identity adoption into a live-table update.
  lifecycle {
    ignore_changes = all
  }
}

resource "routeros_ip_firewall_mangle" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.ip_mangle_rules

  action      = each.value.action
  chain       = each.value.chain
  comment     = each.value.comment
  disabled    = each.value.disabled
  passthrough = each.value.passthrough

  # RouterOS supplies generated counter metadata that the provider normalizes
  # differently across releases. Keep these dynamic rows state-only.
  lifecycle {
    ignore_changes = all
  }
}

# Preserve the RouterOS default bad-address list used by the IPv6 filter
# policy. These entries are policy dependencies, not a reason to leave the
# IPv6 firewall tables outside declarative ownership.
resource "routeros_ipv6_firewall_addr_list" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.ipv6_address_lists

  list     = each.value.list
  address  = each.value.address
  comment  = each.value.comment
  disabled = each.value.disabled
}

resource "routeros_ipv6_firewall_filter" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.ipv6_filter_rules

  action             = each.value.action
  chain              = each.value.chain
  comment            = each.value.comment
  disabled           = each.value.disabled
  log                = each.value.log
  connection_state   = each.value.connection_state
  ipsec_policy       = each.value.ipsec_policy
  src_address        = each.value.src_address
  src_address_list   = each.value.src_address_list
  dst_address        = each.value.dst_address
  dst_address_list   = each.value.dst_address_list
  protocol           = each.value.protocol
  src_port           = each.value.src_port
  dst_port           = each.value.dst_port
  in_interface       = each.value.in_interface
  in_interface_list  = each.value.in_interface_list
  out_interface      = each.value.out_interface
  out_interface_list = each.value.out_interface_list
  hop_limit          = each.value.hop_limit
  headers            = each.value.headers
  reject_with        = each.value.reject_with

  depends_on = [routeros_ipv6_firewall_addr_list.adopted]
}

resource "routeros_ipv6_firewall_nat" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.ipv6_nat_rules

  action        = each.value.action
  chain         = each.value.chain
  comment       = each.value.comment
  disabled      = each.value.disabled
  log           = each.value.log
  src_address   = each.value.src_address
  dst_address   = each.value.dst_address
  protocol      = each.value.protocol
  src_port      = each.value.src_port
  dst_port      = each.value.dst_port
  in_interface  = each.value.in_interface
  out_interface = each.value.out_interface
  ipsec_policy  = each.value.ipsec_policy
  to_address    = each.value.to_address
  to_ports      = each.value.to_ports
}

resource "routeros_ipv6_firewall_mangle" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.ipv6_mangle_rules

  action          = each.value.action
  chain           = each.value.chain
  comment         = each.value.comment
  disabled        = each.value.disabled
  log             = each.value.log
  new_packet_mark = each.value.new_packet_mark
  passthrough     = each.value.passthrough
}

# Input policy starts with connection tracking and service-specific allows so
# the final drop cannot expose a newly enabled RouterOS service accidentally.
resource "routeros_ip_firewall_filter" "input_accept_established" {
  provider = routeros.gw

  action           = "accept"
  chain            = "input"
  connection_state = "established,related,untracked"
  comment          = "sk-firewall/input/accept-established-related"
}

resource "routeros_ip_firewall_filter" "input_drop_invalid" {
  provider = routeros.gw

  action           = "drop"
  chain            = "input"
  connection_state = "invalid"
  comment          = "sk-firewall/input/drop-invalid"
}

resource "routeros_ip_firewall_filter" "input_allow_icmp_trusted" {
  provider          = routeros.gw
  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "icmp"
  comment           = "sk-firewall/input/allow-icmp-trusted"
}

resource "routeros_ip_firewall_filter" "input_allow_loopback" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "input"
  dst_address = "127.0.0.1"
  comment     = "sk-firewall/input/allow-loopback"
}

resource "routeros_ip_firewall_filter" "input_allow_dhcp" {
  provider = routeros.gw
  action   = "accept"
  chain    = "input"
  # DHCP is required by every addressed VLAN, including VLANs 101 and 102
  # that intentionally stay outside the broader LAN policy.
  in_interface_list = var.firewall_policy.internal_interface_list
  protocol          = "udp"
  src_port          = "68"
  dst_port          = "67"
  comment           = "sk-firewall/input/allow-dhcp"

  depends_on = [
    routeros_interface_list.lists,
    routeros_interface_list_member.list_member_internal_vlan,
  ]
}

resource "routeros_ip_firewall_filter" "input_allow_dns_udp" {
  provider          = routeros.gw
  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "udp"
  dst_port          = "53"
  comment           = "sk-firewall/input/allow-dns-udp"
}

resource "routeros_ip_firewall_filter" "input_allow_dns_tcp" {
  provider          = routeros.gw
  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "tcp"
  dst_port          = "53"
  comment           = "sk-firewall/input/allow-dns-tcp"
}

resource "routeros_ip_firewall_filter" "input_allow_ipsec_esp" {
  provider = routeros.gw
  action   = "accept"
  chain    = "input"
  protocol = "ipsec-esp"
  comment  = "sk-firewall/input/allow-ipsec-esp"
}

resource "routeros_ip_firewall_filter" "input_allow_ipsec_handshake" {
  provider = routeros.gw
  action   = "accept"
  chain    = "input"
  protocol = "udp"
  dst_port = "500,4500"
  comment  = "sk-firewall/input/allow-ipsec-handshake"
}

resource "routeros_ip_firewall_filter" "input_allow_kubernetes_bgp" {
  provider         = routeros.gw
  count            = var.kubernetes_bgp.enabled ? 1 : 0
  action           = "accept"
  chain            = "input"
  in_interface     = var.firewall_policy.kubernetes_bgp_interface
  src_address_list = var.firewall_policy.kubernetes_bgp_peer_address_list
  protocol         = "tcp"
  dst_port         = "179"
  comment          = "sk-firewall/input/allow-kubernetes-bgp"

  depends_on = [routeros_ip_firewall_addr_list.kubernetes_bgp_peers]
}

resource "routeros_ip_firewall_filter" "input_allow_snmp_monitoring" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "input"
  src_address = var.firewall_policy.snmp_source_cidr
  protocol    = "udp"
  dst_port    = "161"
  comment     = "sk-firewall/input/allow-snmp-monitoring"
}

resource "routeros_ip_firewall_filter" "input_allow_management" {
  provider         = routeros.gw
  action           = "accept"
  chain            = "input"
  src_address_list = var.firewall_policy.management_address_list
  protocol         = "tcp"
  dst_port         = join(",", sort(tolist(var.firewall_policy.management_ports)))
  comment          = "sk-firewall/input/allow-management"

  depends_on = [routeros_ip_firewall_addr_list.management_sources]
}

resource "routeros_ip_firewall_filter" "input_drop_unmatched" {
  provider = routeros.gw
  action   = "drop"
  chain    = "input"
  comment  = "sk-firewall/input/drop-unmatched"
}

# Forward policy preserves established sessions, IPsec, trusted egress, the
# verified service exceptions, and explicit destination NAT before denying all
# remaining inter-VLAN, WAN, and peer traffic.
resource "routeros_ip_firewall_filter" "forward_fasttrack_established" {
  provider         = routeros.gw
  action           = "fasttrack-connection"
  chain            = "forward"
  connection_state = "established,related"
  comment          = "sk-firewall/forward/fasttrack-established-related"
}

resource "routeros_ip_firewall_filter" "forward_accept_established" {
  provider         = routeros.gw
  action           = "accept"
  chain            = "forward"
  connection_state = "established,related,untracked"
  comment          = "sk-firewall/forward/accept-established-related"
}

resource "routeros_ip_firewall_filter" "forward_drop_invalid" {
  provider         = routeros.gw
  action           = "drop"
  chain            = "forward"
  connection_state = "invalid"
  comment          = "sk-firewall/forward/drop-invalid"
}

resource "routeros_ip_firewall_filter" "forward_allow_ipsec_in" {
  provider     = routeros.gw
  action       = "accept"
  chain        = "forward"
  ipsec_policy = "in,ipsec"
  comment      = "sk-firewall/forward/allow-ipsec-in"
}

resource "routeros_ip_firewall_filter" "forward_allow_ipsec_out" {
  provider     = routeros.gw
  action       = "accept"
  chain        = "forward"
  ipsec_policy = "out,ipsec"
  comment      = "sk-firewall/forward/allow-ipsec-out"
}

resource "routeros_ip_firewall_filter" "forward_allow_trusted_lan_to_wan" {
  provider           = routeros.gw
  action             = "accept"
  chain              = "forward"
  in_interface_list  = var.firewall_policy.trusted_interface_list
  out_interface_list = var.firewall_policy.wan_interface_list
  comment            = "sk-firewall/forward/allow-trusted-lan-to-wan"
}

# Permit every routed VLAN in the inventory to reach only the static Synology
# host. VLAN 100 is excluded because its clients use the local layer-2 path.
resource "routeros_ip_firewall_filter" "forward_allow_synology_from_vlans" {
  provider = routeros.gw
  for_each = local.synology_routed_vlans

  action        = "accept"
  chain         = "forward"
  src_address   = each.value.source_subnet
  dst_address   = var.firewall_policy.synology_address
  in_interface  = each.value.in_interface
  out_interface = try(var.vlans[tostring(var.firewall_policy.synology_vlan_id)].interface_name, null)
  comment       = "sk-firewall/forward/allow-synology-vlan-${each.key}"

  lifecycle {
    precondition {
      condition = alltrue([
        for vlan_id in local.synology_source_vlan_ids :
        contains(keys(var.vlans), tostring(vlan_id)) &&
        vlan_id != var.firewall_policy.synology_vlan_id &&
        try(var.vlans[tostring(vlan_id)].ip_address, null) != null
      ]) && contains(keys(var.vlans), tostring(var.firewall_policy.synology_vlan_id))
      error_message = "Every Synology source VLAN must exist and have a routed address, and the Synology VLAN must exist in the gateway inventory."
    }
  }
}

resource "routeros_ip_firewall_filter" "forward_allow_kubernetes_service_vips" {
  provider          = routeros.gw
  count             = var.kubernetes_bgp.enabled ? 1 : 0
  action            = "accept"
  chain             = "forward"
  in_interface_list = var.firewall_policy.internal_interface_list
  src_address_list  = var.firewall_policy.internal_network_address_list
  dst_address_list  = var.kubernetes_bgp.service_vip_address_list
  # Keep the printer-only SMTP exception meaningful even though the general
  # internal service-VIP rule also covers the Kubernetes VIP address list.
  dst_address = "!${var.firewall_policy.smtp_relay_service_vip}"
  comment     = "sk-firewall/forward/allow-kubernetes-service-vips"

  depends_on = [
    routeros_interface_list.lists,
    routeros_interface_list_member.list_member_internal_vlan,
    routeros_ip_firewall_addr_list.internal_networks,
    routeros_ip_firewall_addr_list.kubernetes_service_vips,
  ]
}

# The remote-access client is explicitly documented to use the Kubernetes DNS
# VIP. Keep this path narrow: only the two verified road-warrior addresses may
# query UDP/TCP 53, and all other WireGuard-to-VLAN traffic remains denied.
resource "routeros_ip_firewall_filter" "forward_allow_wireguard_kubernetes_dns_udp" {
  provider         = routeros.gw
  action           = "accept"
  chain            = "forward"
  src_address_list = var.firewall_policy.wireguard_dns_source_address_list
  dst_address      = var.firewall_policy.wireguard_dns_service_vip
  in_interface     = var.firewall_policy.wireguard_roadwarrior_interface
  protocol         = "udp"
  dst_port         = "53"
  comment          = "sk-firewall/forward/allow-wireguard-kubernetes-dns-udp"
}

resource "routeros_ip_firewall_filter" "forward_allow_wireguard_kubernetes_dns_tcp" {
  provider         = routeros.gw
  action           = "accept"
  chain            = "forward"
  src_address_list = var.firewall_policy.wireguard_dns_source_address_list
  dst_address      = var.firewall_policy.wireguard_dns_service_vip
  in_interface     = var.firewall_policy.wireguard_roadwarrior_interface
  protocol         = "tcp"
  dst_port         = "53"
  comment          = "sk-firewall/forward/allow-wireguard-kubernetes-dns-tcp"
}

# The printer's SMTP relay is a routed Kubernetes VIP. Keep this exception
# limited to the verified printer reservation and submission port; the
# inter-VLAN default deny remains in force for all other printer traffic.
resource "routeros_ip_firewall_filter" "forward_allow_smtp_relay_from_printer" {
  provider          = routeros.gw
  action            = "accept"
  chain             = "forward"
  src_address       = var.firewall_policy.smtp_relay_source_cidr
  dst_address       = var.firewall_policy.smtp_relay_service_vip
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "tcp"
  dst_port          = var.firewall_policy.smtp_relay_port
  comment           = "sk-firewall/forward/allow-smtp-relay-from-printer"
}

# Keep the four existing SNMP resource addresses so their current state can be
# updated in place while the move-items sequence places them before the VLAN
# deny rule.
resource "routeros_ip_firewall_filter" "allow_kubernetes_synology_snmp" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.20.0/24"
  dst_address = "10.1.100.10"
  protocol    = "udp"
  dst_port    = "161"
  # Retain the legacy provider placement attribute so this existing rule is
  # updated in place; routeros_move_items owns the final chain order.
  place_before = 0
  comment      = "Allow Kubernetes worker VLAN to poll Synology SNMP"
}

resource "routeros_ip_firewall_filter" "allow_synology_snmp_responses" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.100.10"
  dst_address = "10.1.20.0/24"
  protocol    = "udp"
  src_port    = "161"
  # Keep the state shape stable during the move-items migration and avoid a
  # provider-forced replacement of this existing exception.
  place_before = routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id
  comment      = "Allow Synology SNMP replies to Kubernetes worker VLAN"
}

resource "routeros_ip_firewall_filter" "allow_kubernetes_unifi_snmp" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.20.0/24"
  dst_address = "10.1.102.0/24"
  protocol    = "udp"
  dst_port    = "161"
  # Keep the state shape stable during the move-items migration and avoid a
  # provider-forced replacement of this existing exception.
  place_before = routeros_ip_firewall_filter.allow_synology_snmp_responses.id
  comment      = "Allow Kubernetes worker VLAN to poll UniFi SNMP"
}

resource "routeros_ip_firewall_filter" "allow_unifi_snmp_responses" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.102.0/24"
  dst_address = "10.1.20.0/24"
  protocol    = "udp"
  src_port    = "161"
  # Keep the state shape stable during the move-items migration and avoid a
  # provider-forced replacement of this existing exception.
  place_before = routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id
  comment      = "Allow UniFi SNMP replies to Kubernetes worker VLAN"
}

# Permit the Proxmox exporter to reach the management API across the routed
# worker and management VLANs before the terminal inter-VLAN deny.
resource "routeros_ip_firewall_filter" "allow_kubernetes_proxmox" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.20.0/24"
  dst_address = "10.1.100.201"
  protocol    = "tcp"
  dst_port    = "8006"
  # A targeted apply cannot run the full move-items resource, so place this
  # exception before the terminal inter-VLAN deny when it is created alone.
  place_before = routeros_ip_firewall_filter.forward_drop_inter_vlan.id
  comment      = "sk-firewall/forward/allow-kubernetes-proxmox"
}

# Give the Dell Server the same narrow Proxmox API path as the original node
# while it uses its new VLAN 100 address.
resource "routeros_ip_firewall_filter" "allow_kubernetes_dell" {
  provider    = routeros.gw
  action      = "accept"
  chain       = "forward"
  src_address = "10.1.20.0/24"
  dst_address = "10.1.100.202"
  protocol    = "tcp"
  dst_port    = "8006"
  # A targeted apply cannot run the full move-items resource, so place this
  # exception before the terminal inter-VLAN deny when it is created alone.
  place_before = routeros_ip_firewall_filter.forward_drop_inter_vlan.id
  comment      = "sk-firewall/forward/allow-kubernetes-dell"
}

# Management forwarding exceptions stay empty by default. Every entry must
# provide a comment so an inter-VLAN allowance is reviewable on the gateway.
resource "routeros_ip_firewall_filter" "forward_management" {
  provider = routeros.gw
  for_each = var.firewall_policy.forward_management_rules

  action             = "accept"
  chain              = "forward"
  comment            = each.value.comment
  disabled           = each.value.disabled
  src_address        = each.value.src_address
  src_address_list   = each.value.src_address_list
  dst_address        = each.value.dst_address
  dst_address_list   = each.value.dst_address_list
  protocol           = each.value.protocol
  src_port           = each.value.src_port
  dst_port           = each.value.dst_port
  in_interface_list  = each.value.in_interface_list
  out_interface_list = each.value.out_interface_list
}

# Preserve the active WAN DST-NAT exception from the live NAT inventory while
# preventing unsolicited new WAN-to-LAN flows from using the general allow.
resource "routeros_ip_firewall_filter" "forward_allow_wan_dstnat" {
  provider             = routeros.gw
  action               = "accept"
  chain                = "forward"
  connection_state     = "new"
  connection_nat_state = "dstnat"
  in_interface_list    = var.firewall_policy.wan_interface_list
  out_interface_list   = var.firewall_policy.trusted_interface_list
  comment              = "sk-firewall/forward/allow-wan-dstnat"
}

resource "routeros_ip_firewall_filter" "forward_drop_inter_vlan" {
  provider           = routeros.gw
  action             = "drop"
  chain              = "forward"
  in_interface_list  = var.firewall_policy.trusted_interface_list
  out_interface_list = var.firewall_policy.trusted_interface_list
  comment            = "sk-firewall/forward/drop-inter-vlan"
}

resource "routeros_ip_firewall_filter" "forward_drop_wan_inbound" {
  provider             = routeros.gw
  action               = "drop"
  chain                = "forward"
  connection_state     = "new"
  connection_nat_state = "!dstnat"
  in_interface_list    = var.firewall_policy.wan_interface_list
  out_interface_list   = var.firewall_policy.trusted_interface_list
  comment              = "sk-firewall/forward/drop-wan-inbound"
}

resource "routeros_ip_firewall_filter" "forward_drop_unmatched" {
  provider = routeros.gw
  action   = "drop"
  chain    = "forward"
  comment  = "sk-firewall/forward/drop-unmatched"
}

# Move-items receives one complete sequence per chain, which makes the policy
# order explicit and avoids a graph of pairwise place-before dependencies.
resource "routeros_move_items" "input_rules" {
  provider      = routeros.gw
  resource_name = "routeros_ip_firewall_filter"
  resource_path = "/ip/firewall/filter"
  # Put connection tracking and the explicit service policy before the terminal
  # deny. Imported legacy/default rules stay represented but are deliberately
  # placed after that deny until their counter-backed cleanup is approved.
  sequence = concat(
    [
      routeros_ip_firewall_filter.input_accept_established.id,
      routeros_ip_firewall_filter.input_drop_invalid.id,
      routeros_ip_firewall_filter.input_allow_loopback.id,
      routeros_ip_firewall_filter.input_allow_dhcp.id,
      routeros_ip_firewall_filter.input_allow_dns_udp.id,
      routeros_ip_firewall_filter.input_allow_dns_tcp.id,
      routeros_ip_firewall_filter.input_allow_icmp_trusted.id,
      routeros_ip_firewall_filter.input_allow_ipsec_esp.id,
      routeros_ip_firewall_filter.input_allow_ipsec_handshake.id,
    ],
    var.kubernetes_bgp.enabled ? [routeros_ip_firewall_filter.input_allow_kubernetes_bgp[0].id] : [],
    [
      routeros_ip_firewall_filter.input_allow_snmp_monitoring.id,
      routeros_ip_firewall_filter.input_allow_management.id,
    ],
    compact([
      for key in local.active_input_adoption_keys : try(routeros_ip_firewall_filter.adopted_input[key].id, null)
    ]),
    [routeros_ip_firewall_filter.input_drop_unmatched.id],
    [
      for key in sort(keys(var.firewall_policy.input_rules)) :
      routeros_ip_firewall_filter.adopted_input[key].id
      if !contains(local.active_input_adoption_keys, key)
    ],
  )

  lifecycle {
    precondition {
      condition     = length(local.input_unmanaged_rule_ids) == 0
      error_message = "Refusing to manage input policy while any live filter rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [
    routeros_ip_firewall_addr_list.kubernetes_bgp_peers,
    routeros_ip_firewall_addr_list.management_sources,
    routeros_ip_firewall_filter.adopted_input,
    routeros_ip_firewall_filter.input_accept_established,
    routeros_ip_firewall_filter.input_drop_invalid,
    routeros_ip_firewall_filter.input_allow_icmp_trusted,
    routeros_ip_firewall_filter.input_allow_loopback,
    routeros_ip_firewall_filter.input_allow_dhcp,
    routeros_ip_firewall_filter.input_allow_dns_udp,
    routeros_ip_firewall_filter.input_allow_dns_tcp,
    routeros_ip_firewall_filter.input_allow_ipsec_esp,
    routeros_ip_firewall_filter.input_allow_ipsec_handshake,
    routeros_ip_firewall_filter.input_allow_kubernetes_bgp,
    routeros_ip_firewall_filter.input_allow_snmp_monitoring,
    routeros_ip_firewall_filter.input_allow_management,
    routeros_ip_firewall_filter.input_drop_unmatched,
  ]
}

resource "routeros_move_items" "forward_rules" {
  provider      = routeros.gw
  resource_name = "routeros_ip_firewall_filter"
  resource_path = "/ip/firewall/filter"
  # IPsec policy exceptions must precede FastTrack. FastTrack then handles
  # eligible established and related flows after their first packet is
  # admitted, including routed Synology and Kubernetes service flows.
  sequence = concat(
    [
      routeros_ip_firewall_filter.forward_allow_ipsec_in.id,
      routeros_ip_firewall_filter.forward_allow_ipsec_out.id,
      routeros_ip_firewall_filter.forward_fasttrack_established.id,
      routeros_ip_firewall_filter.forward_accept_established.id,
      routeros_ip_firewall_filter.forward_drop_invalid.id,
    ],
    [
      for vlan_id in sort(keys(local.synology_routed_vlans)) :
      routeros_ip_firewall_filter.forward_allow_synology_from_vlans[vlan_id].id
    ],
    [routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan.id],
    compact([
      for key in local.active_forward_adoption_keys : try(routeros_ip_firewall_filter.adopted_forward[key].id, null)
    ]),
    var.kubernetes_bgp.enabled ? [routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips[0].id] : [],
    [
      routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_udp.id,
      routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_tcp.id,
      routeros_ip_firewall_filter.forward_allow_smtp_relay_from_printer.id,
      routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id,
      routeros_ip_firewall_filter.allow_synology_snmp_responses.id,
      routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id,
      routeros_ip_firewall_filter.allow_unifi_snmp_responses.id,
      routeros_ip_firewall_filter.allow_kubernetes_proxmox.id,
      routeros_ip_firewall_filter.allow_kubernetes_dell.id,
    ],
    [for rule in values(routeros_ip_firewall_filter.forward_management) : rule.id],
    [
      routeros_ip_firewall_filter.forward_allow_wan_dstnat.id,
      routeros_ip_firewall_filter.forward_drop_inter_vlan.id,
      routeros_ip_firewall_filter.forward_drop_wan_inbound.id,
      routeros_ip_firewall_filter.forward_drop_unmatched.id,
    ],
    [
      for key in sort(keys(var.firewall_policy.forward_rules)) :
      routeros_ip_firewall_filter.adopted_forward[key].id
      if !contains(local.active_forward_adoption_keys, key) &&
      !contains(local.dynamic_forward_adoption_keys, key)
    ],
  )

  lifecycle {
    precondition {
      condition     = length(local.forward_unmanaged_rule_ids) == 0
      error_message = "Refusing to manage forward policy while any live filter rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [
    routeros_ip_firewall_addr_list.adopted,
    routeros_ip_firewall_addr_list.kubernetes_bgp_peers,
    routeros_ip_firewall_addr_list.internal_networks,
    routeros_ip_firewall_filter.adopted_forward,
    routeros_ip_firewall_filter.forward_fasttrack_established,
    routeros_ip_firewall_filter.forward_accept_established,
    routeros_ip_firewall_filter.forward_drop_invalid,
    routeros_ip_firewall_filter.forward_allow_ipsec_in,
    routeros_ip_firewall_filter.forward_allow_ipsec_out,
    routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan,
    routeros_ip_firewall_filter.forward_allow_synology_from_vlans,
    routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips,
    routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_udp,
    routeros_ip_firewall_filter.forward_allow_wireguard_kubernetes_dns_tcp,
    routeros_ip_firewall_filter.forward_allow_smtp_relay_from_printer,
    routeros_ip_firewall_filter.allow_kubernetes_synology_snmp,
    routeros_ip_firewall_filter.allow_synology_snmp_responses,
    routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp,
    routeros_ip_firewall_filter.allow_unifi_snmp_responses,
    routeros_ip_firewall_filter.forward_management,
    routeros_ip_firewall_filter.forward_allow_wan_dstnat,
    routeros_ip_firewall_filter.forward_drop_inter_vlan,
    routeros_ip_firewall_filter.forward_drop_wan_inbound,
    routeros_ip_firewall_filter.forward_drop_unmatched,
  ]
}

# Preserve and declare the current NAT order separately from the filter-chain
# order. NAT rules are first-match policy, so an imported row must not be left
# dependent on the provider's map iteration order.
resource "routeros_move_items" "nat_rules" {
  provider      = routeros.gw
  resource_name = "routeros_ip_firewall_nat"
  resource_path = "/ip/firewall/nat"
  sequence = [
    for key in local.nat_rule_order : routeros_ip_firewall_nat.adopted[key].id
  ]

  lifecycle {
    precondition {
      condition     = length(local.nat_unmanaged_rule_ids) == 0
      error_message = "Refusing to move NAT policy while any live NAT rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [routeros_ip_firewall_nat.adopted]
}

# The provider exposes the IPv4 mangle and IPv6 tables through data sources,
# so fail closed if their live row counts diverge from the imported maps. The
# post-import state/live identity audit covers exact IDs for these tables too.
resource "terraform_data" "ip_mangle_ownership" {
  input = length(data.routeros_ip_firewall.mangle_rules.mangle)

  lifecycle {
    precondition {
      condition     = length(data.routeros_ip_firewall.mangle_rules.mangle) == length(var.firewall_policy.ip_mangle_rules)
      error_message = "Refusing to manage IP mangle policy while any live rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [routeros_ip_firewall_mangle.adopted]
}

resource "routeros_move_items" "ipv6_filter_rules" {
  provider      = routeros.gw
  resource_name = "routeros_ipv6_firewall_filter"
  resource_path = "/ipv6/firewall/filter"
  sequence = [
    for key in local.ipv6_filter_rule_order : routeros_ipv6_firewall_filter.adopted[key].id
  ]

  lifecycle {
    precondition {
      condition     = length(local.ipv6_filter_unmanaged_rule_ids) == 0
      error_message = "Refusing to move IPv6 filter policy while any live rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [routeros_ipv6_firewall_filter.adopted]
}

resource "terraform_data" "ipv6_nat_ownership" {
  input = length(data.routeros_ipv6_firewall.rules.nat)

  lifecycle {
    precondition {
      condition     = length(data.routeros_ipv6_firewall.rules.nat) == length(var.firewall_policy.ipv6_nat_rules)
      error_message = "Refusing to manage IPv6 NAT policy while any live rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [routeros_ipv6_firewall_nat.adopted]
}

resource "terraform_data" "ipv6_mangle_ownership" {
  input = length(data.routeros_ipv6_firewall.rules.mangle)

  lifecycle {
    precondition {
      condition     = length(data.routeros_ipv6_firewall.rules.mangle) == length(var.firewall_policy.ipv6_mangle_rules)
      error_message = "Refusing to manage IPv6 mangle policy while any live rule remains outside OpenTofu ownership."
    }
  }

  depends_on = [routeros_ipv6_firewall_mangle.adopted]
}

# The RouterOS provider has no raw-table data source. Keep the single dynamic
# raw counter row state-owned and inventory it on every trusted baseline run;
# unlike normal policy tables, it is intentionally never sent to /move.
resource "terraform_data" "raw_ownership" {
  input = sort(keys(var.firewall_policy.raw_rules))

  depends_on = [routeros_ip_firewall_raw.adopted]
}

resource "terraform_data" "bridge_filter_ownership" {
  input = length(data.routeros_interface_bridge_filter.rules.filters)

  lifecycle {
    precondition {
      condition     = length(data.routeros_interface_bridge_filter.rules.filters) == 0
      error_message = "Refusing to manage firewall policy while any live bridge-filter rule remains outside OpenTofu ownership."
    }
  }
}
