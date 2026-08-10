# Read both built-in chains before creating policy rules so new rules can be
# inserted before the first unmanaged rule without relying on RouterOS numeric
# positions. Managed comments are excluded from the anchor calculation on later
# plans, which avoids the self-referential ordering failure seen in PR #174.
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
  # Include both the current SNMP comments and the new stable comments so the
  # existing managed resources are never selected as their own ordering anchor
  # during the first migration plan.
  firewall_managed_comments = toset(concat([
    "Allow Kubernetes worker VLAN to poll Synology SNMP",
    "Allow Synology SNMP replies to Kubernetes worker VLAN",
    "Allow Kubernetes worker VLAN to poll UniFi SNMP",
    "Allow UniFi SNMP replies to Kubernetes worker VLAN",
    "sk-firewall/input/accept-established-related",
    "sk-firewall/input/drop-invalid",
    "sk-firewall/input/allow-icmp-trusted",
    "sk-firewall/input/allow-dhcp",
    "sk-firewall/input/allow-kubernetes-bgp",
    "sk-firewall/input/allow-snmp-monitoring",
    "sk-firewall/input/allow-management",
    "sk-firewall/input/allow-wireguard",
    "sk-firewall/input/drop-unmatched",
    "sk-firewall/forward/accept-established-related",
    "sk-firewall/forward/drop-invalid",
    "sk-firewall/forward/allow-trusted-lan-to-wan",
    "sk-firewall/forward/allow-wireguard-to-trusted-lan",
    "sk-firewall/forward/allow-kubernetes-service-vips",
    "sk-firewall/forward/allow-kubernetes-synology-snmp",
    "sk-firewall/forward/allow-synology-snmp-responses",
    "sk-firewall/forward/allow-kubernetes-unifi-snmp",
    "sk-firewall/forward/allow-unifi-snmp-responses",
    "sk-firewall/forward/drop-inter-vlan",
    "sk-firewall/forward/drop-wan-inbound",
    "sk-firewall/forward/drop-unmatched",
    ], [
    for rule in values(var.firewall_policy.forward_management_rules) : rule.comment
  ]))

  # Use a stable first unmanaged rule as the tail anchor. An empty chain is
  # safe to append to; a non-empty chain must always retain its live anchor.
  input_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.input_rules.rules : rule.id
    if !contains(local.firewall_managed_comments, try(rule.comment, ""))
  ]
  forward_unmanaged_rule_ids = [
    for rule in data.routeros_ip_firewall.forward_rules.rules : rule.id
    if !contains(local.firewall_managed_comments, try(rule.comment, ""))
  ]
  input_anchor   = try(local.input_unmanaged_rule_ids[0], null)
  forward_anchor = try(local.forward_unmanaged_rule_ids[0], null)

  # Address-list members are represented as separate resources so each
  # Kubernetes peer and management source remains independently reviewable.
  kubernetes_bgp_addresses = {
    for address in var.firewall_policy.kubernetes_node_addresses :
    replace(address, ".", "_") => address
  }
  management_sources = merge(
    {
      vlan100 = {
        address = var.firewall_policy.management_source_cidr
        comment = "RouterOS management sources on VLAN 100"
      }
    },
    var.firewall_policy.wireguard.enabled ? {
      wireguard = {
        address = var.firewall_policy.wireguard.source_cidr
        comment = "RouterOS management sources from WireGuard"
      }
    } : {}
  )

  # The optional WireGuard rule is inserted into the same ordered chain when
  # inventory-backed values are enabled; otherwise the next managed rule is the
  # direct ordering anchor.
  input_wireguard_anchor = try(
    routeros_ip_firewall_filter.input_allow_wireguard[0].id,
    routeros_ip_firewall_filter.input_allow_management.id,
  )
  forward_service_vip_anchor = try(
    routeros_ip_firewall_filter.forward_allow_kubernetes_service_vips[0].id,
    routeros_ip_firewall_filter.allow_unifi_snmp_responses.id,
  )
  forward_wireguard_anchor = try(
    routeros_ip_firewall_filter.forward_allow_wireguard_to_trusted_lan[0].id,
    local.forward_service_vip_anchor,
  )
  forward_management_keys = sort(keys(var.firewall_policy.forward_management_rules))
  forward_management_anchor = try(
    routeros_ip_firewall_filter.forward_management[local.forward_management_keys[0]].id,
    routeros_ip_firewall_filter.forward_drop_inter_vlan.id,
  )
}

# Keep BGP peer identity separate from the route-policy address list so the
# firewall can restrict TCP/179 without changing accepted Kubernetes routes.
resource "routeros_ip_firewall_addr_list" "kubernetes_bgp_peers" {
  provider = routeros.gw
  for_each = local.kubernetes_bgp_addresses

  list    = "sk-kubernetes-bgp-peers"
  address = each.value
  comment = "Kubernetes BGP peer ${each.value}"
}

# Management sources include the existing VLAN 100 administration network and,
# only after inventory enables it, the WireGuard remote-access network.
resource "routeros_ip_firewall_addr_list" "management_sources" {
  provider = routeros.gw
  for_each = local.management_sources

  list    = "sk-router-management-sources"
  address = each.value.address
  comment = each.value.comment
}

# Input policy starts with state handling and ends in an explicit deny so a new
# RouterOS service cannot become reachable merely by listening on a port.
resource "routeros_ip_firewall_filter" "input_accept_established" {
  provider = routeros.gw

  action           = "accept"
  chain            = "input"
  connection_state = "established,related"
  place_before     = routeros_ip_firewall_filter.input_drop_invalid.id
  comment          = "sk-firewall/input/accept-established-related"
}

resource "routeros_ip_firewall_filter" "input_drop_invalid" {
  provider = routeros.gw

  action           = "drop"
  chain            = "input"
  connection_state = "invalid"
  place_before     = routeros_ip_firewall_filter.input_allow_icmp_trusted.id
  comment          = "sk-firewall/input/drop-invalid"
}

resource "routeros_ip_firewall_filter" "input_allow_icmp_trusted" {
  provider = routeros.gw

  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "icmp"
  place_before      = routeros_ip_firewall_filter.input_allow_dhcp.id
  comment           = "sk-firewall/input/allow-icmp-trusted"
}

resource "routeros_ip_firewall_filter" "input_allow_dhcp" {
  provider = routeros.gw

  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.trusted_interface_list
  protocol          = "udp"
  src_port          = "68"
  dst_port          = "67"
  place_before      = routeros_ip_firewall_filter.input_allow_kubernetes_bgp.id
  comment           = "sk-firewall/input/allow-dhcp"
}

resource "routeros_ip_firewall_filter" "input_allow_kubernetes_bgp" {
  provider = routeros.gw

  action           = "accept"
  chain            = "input"
  in_interface     = var.firewall_policy.kubernetes_bgp_interface
  protocol         = "tcp"
  dst_port         = "179"
  src_address_list = "sk-kubernetes-bgp-peers"
  place_before     = routeros_ip_firewall_filter.input_allow_snmp_monitoring.id
  comment          = "sk-firewall/input/allow-kubernetes-bgp"
  depends_on       = [routeros_ip_firewall_addr_list.kubernetes_bgp_peers]
}

resource "routeros_ip_firewall_filter" "input_allow_snmp_monitoring" {
  provider = routeros.gw

  action       = "accept"
  chain        = "input"
  src_address  = var.firewall_policy.snmp_source_cidr
  protocol     = "udp"
  dst_port     = "161"
  place_before = local.input_wireguard_anchor
  comment      = "sk-firewall/input/allow-snmp-monitoring"
}

resource "routeros_ip_firewall_filter" "input_allow_management" {
  provider = routeros.gw

  action           = "accept"
  chain            = "input"
  src_address_list = "sk-router-management-sources"
  protocol         = "tcp"
  dst_port         = join(",", sort(tolist(var.firewall_policy.management_ports)))
  place_before     = routeros_ip_firewall_filter.input_drop_unmatched.id
  comment          = "sk-firewall/input/allow-management"
  depends_on       = [routeros_ip_firewall_addr_list.management_sources]
}

resource "routeros_ip_firewall_filter" "input_allow_wireguard" {
  provider = routeros.gw
  count    = var.firewall_policy.wireguard.enabled ? 1 : 0

  action            = "accept"
  chain             = "input"
  in_interface_list = var.firewall_policy.wan_interface_list
  protocol          = "udp"
  dst_port          = var.firewall_policy.wireguard.listen_port
  place_before      = routeros_ip_firewall_filter.input_allow_management.id
  comment           = "sk-firewall/input/allow-wireguard"
}

resource "routeros_ip_firewall_filter" "input_drop_unmatched" {
  provider = routeros.gw

  action       = "drop"
  chain        = "input"
  place_before = local.input_anchor
  comment      = "sk-firewall/input/drop-unmatched"

  lifecycle {
    precondition {
      condition     = local.input_anchor != null || length(local.input_unmanaged_rule_ids) == 0
      error_message = "Refusing to append input default-deny rules while unmanaged input rules exist without a stable anchor."
    }
  }
}

# Forward policy allows trusted LAN egress and remote-access traffic first, then
# preserves the narrow SNMP exceptions before explicit inter-VLAN and WAN drops.
resource "routeros_ip_firewall_filter" "forward_accept_established" {
  provider = routeros.gw

  action           = "accept"
  chain            = "forward"
  connection_state = "established,related"
  place_before     = routeros_ip_firewall_filter.forward_drop_invalid.id
  comment          = "sk-firewall/forward/accept-established-related"
}

resource "routeros_ip_firewall_filter" "forward_drop_invalid" {
  provider = routeros.gw

  action           = "drop"
  chain            = "forward"
  connection_state = "invalid"
  place_before     = routeros_ip_firewall_filter.forward_allow_trusted_lan_to_wan.id
  comment          = "sk-firewall/forward/drop-invalid"
}

resource "routeros_ip_firewall_filter" "forward_allow_trusted_lan_to_wan" {
  provider = routeros.gw

  action             = "accept"
  chain              = "forward"
  in_interface_list  = var.firewall_policy.trusted_interface_list
  out_interface_list = var.firewall_policy.wan_interface_list
  place_before       = local.forward_wireguard_anchor
  comment            = "sk-firewall/forward/allow-trusted-lan-to-wan"
}

resource "routeros_ip_firewall_filter" "forward_allow_wireguard_to_trusted_lan" {
  provider = routeros.gw
  count    = var.firewall_policy.wireguard.enabled ? 1 : 0

  action             = "accept"
  chain              = "forward"
  in_interface       = var.firewall_policy.wireguard.interface_name
  out_interface_list = var.firewall_policy.trusted_interface_list
  src_address        = var.firewall_policy.wireguard.source_cidr
  place_before       = local.forward_service_vip_anchor
  comment            = "sk-firewall/forward/allow-wireguard-to-trusted-lan"
}

resource "routeros_ip_firewall_filter" "forward_allow_kubernetes_service_vips" {
  provider = routeros.gw
  count    = var.kubernetes_bgp.enabled ? 1 : 0

  action            = "accept"
  chain             = "forward"
  in_interface_list = var.firewall_policy.trusted_interface_list
  dst_address_list  = var.firewall_policy.service_vip_address_list
  place_before      = routeros_ip_firewall_filter.allow_unifi_snmp_responses.id
  comment           = "sk-firewall/forward/allow-kubernetes-service-vips"
  depends_on        = [routeros_ip_firewall_addr_list.kubernetes_service_vips]
}

# Keep existing SNMP exception resource addresses stable while moving the group
# behind the general service-VIP allowance and ahead of explicit inter-VLAN deny.
resource "routeros_ip_firewall_filter" "allow_kubernetes_synology_snmp" {
  provider = routeros.gw

  action       = "accept"
  chain        = "forward"
  src_address  = "10.1.20.0/24"
  dst_address  = "10.1.100.10"
  protocol     = "udp"
  dst_port     = "161"
  place_before = local.forward_management_anchor
  comment      = "sk-firewall/forward/allow-kubernetes-synology-snmp"
}

resource "routeros_ip_firewall_filter" "allow_synology_snmp_responses" {
  provider = routeros.gw

  action       = "accept"
  chain        = "forward"
  src_address  = "10.1.100.10"
  dst_address  = "10.1.20.0/24"
  protocol     = "udp"
  src_port     = "161"
  place_before = routeros_ip_firewall_filter.allow_kubernetes_synology_snmp.id
  comment      = "sk-firewall/forward/allow-synology-snmp-responses"
}

resource "routeros_ip_firewall_filter" "allow_kubernetes_unifi_snmp" {
  provider = routeros.gw

  action       = "accept"
  chain        = "forward"
  src_address  = "10.1.20.0/24"
  dst_address  = "10.1.102.0/24"
  protocol     = "udp"
  dst_port     = "161"
  place_before = routeros_ip_firewall_filter.allow_synology_snmp_responses.id
  comment      = "sk-firewall/forward/allow-kubernetes-unifi-snmp"
}

resource "routeros_ip_firewall_filter" "allow_unifi_snmp_responses" {
  provider = routeros.gw

  action       = "accept"
  chain        = "forward"
  src_address  = "10.1.102.0/24"
  dst_address  = "10.1.20.0/24"
  protocol     = "udp"
  src_port     = "161"
  place_before = routeros_ip_firewall_filter.allow_kubernetes_unifi_snmp.id
  comment      = "sk-firewall/forward/allow-unifi-snmp-responses"
}

# Keep future management exceptions explicit and map-driven; an empty map is
# safer than guessing allowed inter-VLAN ports from device names.
resource "routeros_ip_firewall_filter" "forward_management" {
  provider = routeros.gw
  for_each = var.firewall_policy.forward_management_rules

  action             = "accept"
  chain              = "forward"
  src_address        = try(each.value.src_address, null)
  src_address_list   = try(each.value.src_address_list, null)
  dst_address        = try(each.value.dst_address, null)
  dst_address_list   = try(each.value.dst_address_list, null)
  protocol           = try(each.value.protocol, null)
  src_port           = try(each.value.src_port, null)
  dst_port           = try(each.value.dst_port, null)
  in_interface_list  = try(each.value.in_interface_list, null)
  out_interface_list = try(each.value.out_interface_list, null)
  place_before       = routeros_ip_firewall_filter.forward_drop_inter_vlan.id
  comment            = each.value.comment
}

resource "routeros_ip_firewall_filter" "forward_drop_inter_vlan" {
  provider = routeros.gw

  action             = "drop"
  chain              = "forward"
  in_interface_list  = var.firewall_policy.trusted_interface_list
  out_interface_list = var.firewall_policy.trusted_interface_list
  place_before       = routeros_ip_firewall_filter.forward_drop_wan_inbound.id
  comment            = "sk-firewall/forward/drop-inter-vlan"
}

resource "routeros_ip_firewall_filter" "forward_drop_wan_inbound" {
  provider = routeros.gw

  action             = "drop"
  chain              = "forward"
  in_interface_list  = var.firewall_policy.wan_interface_list
  out_interface_list = var.firewall_policy.trusted_interface_list
  place_before       = routeros_ip_firewall_filter.forward_drop_unmatched.id
  comment            = "sk-firewall/forward/drop-wan-inbound"
}

resource "routeros_ip_firewall_filter" "forward_drop_unmatched" {
  provider = routeros.gw

  action       = "drop"
  chain        = "forward"
  place_before = local.forward_anchor
  comment      = "sk-firewall/forward/drop-unmatched"

  lifecycle {
    precondition {
      condition     = local.forward_anchor != null || length(local.forward_unmanaged_rule_ids) == 0
      error_message = "Refusing to append forward default-deny rules while unmanaged forward rules exist without a stable anchor."
    }
  }
}
