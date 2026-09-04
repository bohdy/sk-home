# Read the live chains so the managed policy can be placed before the first
# unmanaged rule without relying on volatile numeric positions.
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

locals {
  # Stable comments identify newly managed rules on later plans. Existing
  # adopted IDs below cover the first cutover, when their old comments have not
  # yet been replaced by the stable policy comments.
  firewall_managed_comments = toset(compact(concat([
    "Allow Kubernetes worker VLAN to poll Synology SNMP",
    "Allow Synology SNMP replies to Kubernetes worker VLAN",
    "Allow Kubernetes worker VLAN to poll UniFi SNMP",
    "Allow UniFi SNMP replies to Kubernetes worker VLAN",
    "sk-firewall/input/accept-established-related",
    "sk-firewall/input/drop-invalid",
    "sk-firewall/input/allow-icmp-trusted",
    "sk-firewall/input/allow-loopback",
    "sk-firewall/input/allow-dhcp",
    "sk-firewall/input/allow-dns-udp",
    "sk-firewall/input/allow-dns-tcp",
    "sk-firewall/input/allow-ipsec-esp",
    "sk-firewall/input/allow-ipsec-handshake",
    "sk-firewall/input/allow-kubernetes-bgp",
    "sk-firewall/input/allow-snmp-monitoring",
    "sk-firewall/input/allow-management",
    "sk-firewall/input/drop-unmatched",
    "sk-firewall/forward/fasttrack-established-related",
    "sk-firewall/forward/accept-established-related",
    "sk-firewall/forward/drop-invalid",
    "sk-firewall/forward/allow-ipsec-in",
    "sk-firewall/forward/allow-ipsec-out",
    "sk-firewall/forward/allow-trusted-lan-to-wan",
    "sk-firewall/forward/allow-kubernetes-service-vips",
    "sk-firewall/forward/allow-wan-dstnat",
    "sk-firewall/forward/drop-inter-vlan",
    "sk-firewall/forward/drop-wan-inbound",
    "sk-firewall/forward/drop-unmatched",
    ], [
    for rule in concat(
      values(var.firewall_policy.input_rules),
      values(var.firewall_policy.forward_rules),
    ) : try(rule.comment, null)
  ])))

  # Existing adopted resources are excluded by ID during the first cutover.
  # Once their comments are updated, the stable comment filter keeps them out
  # of the anchor calculation without a dependency on their state IDs.
  existing_input_rule_ids = [
    for rule in values(routeros_ip_firewall_filter.adopted_input) : rule.id
  ]
  existing_forward_rule_ids = concat(
    [for rule in values(routeros_ip_firewall_filter.adopted_forward) : rule.id],
    [
      routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id,
      routeros_ip_firewall_filter.allow_synology_snmp_responses.id,
      routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id,
      routeros_ip_firewall_filter.allow_unifi_snmp_responses.id,
    ],
  )

  input_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.input_rules.rules : rule.id
    if !contains(local.existing_input_rule_ids, rule.id) &&
    !contains(local.firewall_managed_comments, try(rule.comment, ""))
  ]
  forward_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.forward_rules.rules : rule.id
    if !contains(local.existing_forward_rule_ids, rule.id) &&
    !contains(local.firewall_managed_comments, try(rule.comment, ""))
  ]
  input_anchor   = try(local.input_unmanaged_rule_ids[0], null)
  forward_anchor = try(local.forward_unmanaged_rule_ids[0], null)

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

  # The map's disabled flag controls whether an adopted input exception stays
  # active. Sorting makes additional reviewed exceptions deterministic while
  # keeping disabled legacy rules behind the terminal deny.
  active_input_adoption_keys = [
    for key in sort(keys(var.firewall_policy.input_rules)) : key
    if !var.firewall_policy.input_rules[key].disabled
  ]
  disabled_input_adoption_keys = [
    for key in sort(keys(var.firewall_policy.input_rules)) : key
    if !contains(local.active_input_adoption_keys, key)
  ]

  # Keep the verified forward exceptions in a deliberate order instead of
  # relying on map iteration order. Additional reviewed exceptions are appended
  # deterministically after these baseline paths.
  baseline_forward_adoption_keys = [
    for key in [
      "site_to_site",
      "known_wan",
      "wireguard_roadwarrior_to_trusted_lan",
      "wireguard_site_to_site_to_trusted_lan",
    ] : key if contains(keys(var.firewall_policy.forward_rules), key)
  ]
  additional_forward_adoption_keys = [
    for key in sort(keys(var.firewall_policy.forward_rules)) : key
    if !contains(local.baseline_forward_adoption_keys, key)
  ]
  ordered_forward_adoption_keys = concat(
    local.baseline_forward_adoption_keys,
    local.additional_forward_adoption_keys,
  )
  ordered_forward_management_keys = sort(keys(var.firewall_policy.forward_management_rules))
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
  provider          = routeros.gw
  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "udp"
  src_port          = "68"
  dst_port          = "67"
  comment           = "sk-firewall/input/allow-dhcp"
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

  lifecycle {
    precondition {
      condition     = local.input_anchor != null || length(local.input_unmanaged_rule_ids) == 0
      error_message = "Refusing to order input policy without a stable unmanaged-rule anchor."
    }
  }
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

resource "routeros_ip_firewall_filter" "forward_allow_kubernetes_service_vips" {
  provider          = routeros.gw
  count             = var.kubernetes_bgp.enabled ? 1 : 0
  action            = "accept"
  chain             = "forward"
  in_interface_list = var.firewall_policy.trusted_interface_list
  dst_address_list  = var.kubernetes_bgp.service_vip_address_list
  comment           = "sk-firewall/forward/allow-kubernetes-service-vips"

  depends_on = [routeros_ip_firewall_addr_list.kubernetes_service_vips]
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

  lifecycle {
    precondition {
      condition     = local.forward_anchor != null || length(local.forward_unmanaged_rule_ids) == 0
      error_message = "Refusing to order forward policy without a stable unmanaged-rule anchor."
    }
  }
}

# Move-items receives one complete sequence per chain, which makes the policy
# order explicit and avoids a graph of pairwise place-before dependencies.
resource "routeros_move_items" "input_rules" {
  provider      = routeros.gw
  resource_name = "routeros_ip_firewall_filter"
  resource_path = "/ip/firewall/filter"
  sequence = concat(
    [
      routeros_ip_firewall_filter.input_accept_established.id,
      routeros_ip_firewall_filter.input_drop_invalid.id,
      routeros_ip_firewall_filter.input_allow_icmp_trusted.id,
      routeros_ip_firewall_filter.input_allow_loopback.id,
      routeros_ip_firewall_filter.input_allow_dhcp.id,
      routeros_ip_firewall_filter.input_allow_dns_udp.id,
      routeros_ip_firewall_filter.input_allow_dns_tcp.id,
      routeros_ip_firewall_filter.input_allow_ipsec_esp.id,
      routeros_ip_firewall_filter.input_allow_ipsec_handshake.id,
    ],
    var.kubernetes_bgp.enabled ? [routeros_ip_firewall_filter.input_allow_kubernetes_bgp[0].id] : [],
    [
      routeros_ip_firewall_filter.input_allow_snmp_monitoring.id,
      routeros_ip_firewall_filter.input_allow_management.id,
    ],
    [
      for key in local.active_input_adoption_keys :
      routeros_ip_firewall_filter.adopted_input[key].id
    ],
    [routeros_ip_firewall_filter.input_drop_unmatched.id],
    [
      for key in local.disabled_input_adoption_keys :
      routeros_ip_firewall_filter.adopted_input[key].id
    ],
    local.input_anchor == null ? [] : [local.input_anchor],
  )

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
  sequence = concat(
    [
      routeros_ip_firewall_filter.forward_fasttrack_established.id,
      routeros_ip_firewall_filter.forward_accept_established.id,
      routeros_ip_firewall_filter.forward_drop_invalid.id,
      routeros_ip_firewall_filter.forward_allow_ipsec_in.id,
      routeros_ip_firewall_filter.forward_allow_ipsec_out.id,
      routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan.id,
    ],
    [
      for key in local.ordered_forward_adoption_keys :
      routeros_ip_firewall_filter.adopted_forward[key].id
    ],
    var.kubernetes_bgp.enabled ? [routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips[0].id] : [],
    [
      routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id,
      routeros_ip_firewall_filter.allow_synology_snmp_responses.id,
      routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id,
      routeros_ip_firewall_filter.allow_unifi_snmp_responses.id,
    ],
    [
      for key in local.ordered_forward_management_keys :
      routeros_ip_firewall_filter.forward_management[key].id
    ],
    [
      routeros_ip_firewall_filter.forward_allow_wan_dstnat.id,
      routeros_ip_firewall_filter.forward_drop_inter_vlan.id,
      routeros_ip_firewall_filter.forward_drop_wan_inbound.id,
      routeros_ip_firewall_filter.forward_drop_unmatched.id,
    ],
    local.forward_anchor == null ? [] : [local.forward_anchor],
  )

  depends_on = [
    routeros_ip_firewall_addr_list.adopted,
    routeros_ip_firewall_addr_list.kubernetes_bgp_peers,
    routeros_ip_firewall_filter.adopted_forward,
    routeros_ip_firewall_filter.forward_fasttrack_established,
    routeros_ip_firewall_filter.forward_accept_established,
    routeros_ip_firewall_filter.forward_drop_invalid,
    routeros_ip_firewall_filter.forward_allow_ipsec_in,
    routeros_ip_firewall_filter.forward_allow_ipsec_out,
    routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan,
    routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips,
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
