# Adopt only the verified static firewall exceptions from the live baseline.
# This first migration deliberately does not add a new default-deny policy or
# reorder the existing RouterOS chain; those changes require a separate design
# and acceptance stage after state ownership is established.
resource "routeros_ip_firewall_addr_list" "adopted" {
  provider = routeros.gw
  for_each = var.firewall_policy.address_lists

  list    = each.value.list
  address = each.value.address
  comment = each.value.comment
}

# Keep input rule adoption map-driven so every matcher is visible in one
# non-secret variable object and can be imported without an imperative update.
resource "routeros_ip_firewall_filter" "adopted_input" {
  provider = routeros.gw
  for_each = var.firewall_policy.input_rules

  action               = each.value.action
  chain                = "input"
  comment              = each.value.comment
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
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

# Forward adoption preserves the existing site-to-site and known-WAN paths
# without inventing new inter-VLAN or public-ingress allowances.
resource "routeros_ip_firewall_filter" "adopted_forward" {
  provider = routeros.gw
  for_each = var.firewall_policy.forward_rules

  action               = each.value.action
  chain                = "forward"
  comment              = each.value.comment
  connection_state     = each.value.connection_state
  connection_nat_state = each.value.connection_nat_state
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
  depends_on           = [routeros_ip_firewall_addr_list.adopted]
}

# These four SNMP exceptions were already OpenTofu-owned. Keep their resource
# addresses and live matchers stable while the rest of the baseline is adopted.
resource "routeros_ip_firewall_filter" "allow_kubernetes_synology_snmp" {
  provider = routeros.gw

  action       = "accept"
  chain        = "forward"
  src_address  = "10.1.20.0/24"
  dst_address  = "10.1.100.10"
  protocol     = "udp"
  dst_port     = "161"
  place_before = 0
  comment      = "Allow Kubernetes worker VLAN to poll Synology SNMP"
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
  comment      = "Allow Synology SNMP replies to Kubernetes worker VLAN"
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
  comment      = "Allow Kubernetes worker VLAN to poll UniFi SNMP"
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
  comment      = "Allow UniFi SNMP replies to Kubernetes worker VLAN"
}
