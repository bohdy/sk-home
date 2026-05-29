// Build the gateway around one primary bridge so VLAN policy and access-port
// behavior stay centralized on the RouterOS side.
resource "routeros_interface_bridge" "bridge" {
  provider       = routeros.gw
  name           = "bridge"
  comment        = "Primary LAN bridge"
  arp            = "enabled"
  admin_mac      = "18:FD:74:CF:73:F0"
  vlan_filtering = true
  fast_forward   = true
}

// Attach interfaces with a PVID to the shared bridge while preserving a
// per-port PVID for untagged ingress traffic. Interfaces without a PVID are
// not attached to the bridge.
resource "routeros_interface_bridge_port" "bridge_port_ethernet" {
  for_each = {
    for k, v in var.interfaces : k => v if v.pvid != null && v.pvid != 0
  }
  provider  = routeros.gw
  bridge    = routeros_interface_bridge.bridge.name
  interface = each.value.name
  comment   = each.value.name
  pvid      = each.value.pvid
}

// Mirror the declarative interface inventory into RouterOS so comment metadata
// and port naming stay consistent with the bridge membership map.
resource "routeros_interface_ethernet" "ethernet" {
  for_each     = var.interfaces
  provider     = routeros.gw
  factory_name = each.value.name
  name         = each.value.name
  comment      = each.value.comment
}

resource "routeros_interface_vlan" "iface_vlan" {
  for_each = var.vlans
  provider = routeros.gw
  name     = "vlan${each.key}"
  // Terminate each VLAN on the shared bridge so Layer 3 services can bind to
  // the logical VLAN interface rather than to a specific access port.
  // interface = "vlan${each.key}"
  interface = routeros_interface_bridge.bridge.name
  comment   = each.value.name
}

// Materialize the VLAN inventory onto the bridge from one source of truth,
// ensuring trunk membership and access-port exposure can be reviewed in code.
resource "routeros_interface_bridge_vlan" "bridge_vlan" {
  for_each = var.vlans
  provider = routeros.gw
  vlan_ids = [tonumber(each.key)]
  bridge   = routeros_interface_bridge.bridge.name
  tagged   = setunion([routeros_interface_bridge.bridge.name], each.value.tagged)
  untagged = each.value.untagged
  comment  = each.value.name
}

resource "routeros_ip_address" "ip_address" {
  for_each = {
    for k, v in var.interfaces : k => v if v.ip_address != null
  }
  // Only interfaces with explicit Layer 3 addresses participate here; pure
  // switchports stay absent so the inventory can represent both routed and
  // bridged ports in one map.
  provider  = routeros.gw
  address   = each.value.ip_address
  interface = each.value.name
  comment   = each.value.comment
}

resource "routeros_ip_address" "ip_address_vlan" {
  for_each = {
    for k, v in var.vlans : k => v if v.ip_address != null
  }
  // Bind IP addresses to the generated VLAN interfaces so gateway subnets are
  // managed from the same VLAN inventory that drives bridge tagging rules.
  provider  = routeros.gw
  address   = each.value.ip_address
  interface = "vlan${each.key}"
  comment   = each.value.name
}

// Collect all unique interface list names referenced across interfaces and vlans
// to ensure all required lists are created before members are assigned.
locals {
  interface_lists = {
    for name in distinct(concat(
      [for v in var.interfaces : v.iface_list if v.iface_list != null],
      [for v in var.vlans : v.iface_list if v.iface_list != null]
    )) : name => true
  }

  # Expand the optional BGP node inventory only when Kubernetes peering is
  # enabled so disabling the feature removes all BGP resources in one place.
  kubernetes_bgp_nodes = var.kubernetes_bgp.enabled ? var.kubernetes_bgp.nodes : {}
}

// Create all required interface lists dynamically from the merged local to ensure
// they exist before members are assigned.
resource "routeros_interface_list" "lists" {
  for_each = local.interface_lists
  provider = routeros.gw
  name     = each.key
}

resource "routeros_interface_list_member" "list_member_ether" {
  provider = routeros.gw
  for_each = {
    for k, v in var.interfaces : k => v if v.iface_list != null
  }
  // Use the map key as the member name so the list membership stays aligned
  // with the same stable identifier used throughout the interface inventory.
  interface = each.key
  list      = each.value.iface_list
}

resource "routeros_interface_list_member" "list_member_vlan" {
  provider = routeros.gw
  for_each = {
    for k, v in var.vlans : k => v if v.iface_list != null
  }
  // VLAN-backed interface lists are derived from the VLAN ID key because the
  // RouterOS interface name is generated deterministically as vlan<ID>.
  interface = "vlan${each.key}"
  list      = each.value.iface_list
}

resource "routeros_ip_firewall_addr_list" "kubernetes_service_vips" {
  count    = var.kubernetes_bgp.enabled ? 1 : 0
  provider = routeros.gw

  # RouterOS can pre-filter received BGP NLRIs against this list before normal
  # route-filter evaluation, which keeps unexpected Kubernetes routes out early.
  list    = var.kubernetes_bgp.service_vip_address_list
  address = var.kubernetes_bgp.service_vip_cidr
  comment = "Kubernetes LoadBalancer VIPs advertised by Cilium"
}

resource "routeros_routing_filter_rule" "kubernetes_bgp_in" {
  count    = var.kubernetes_bgp.enabled ? 1 : 0
  provider = routeros.gw

  # Cilium advertises LoadBalancer VIPs as host routes by default. Rejecting
  # everything else makes route leaks fail closed even when a node is mis-set.
  chain   = var.kubernetes_bgp.input_filter_chain
  rule    = "if (dst in ${var.kubernetes_bgp.service_vip_cidr} && dst-len == 32) { accept } else { reject }"
  comment = "Accept only Kubernetes LoadBalancer VIP host routes"
}

resource "routeros_routing_bgp_connection" "kubernetes_node" {
  for_each = local.kubernetes_bgp_nodes
  provider = routeros.gw

  # Each Talos node runs Cilium's BGP control plane and peers directly with the
  # gateway over VLAN 20 using iBGP in the homelab private ASN.
  name             = "kubernetes-${each.key}"
  as               = tostring(var.kubernetes_bgp.local_asn)
  address_families = "ip"
  comment          = "Kubernetes BGP peer ${each.value.comment}"
  connect          = true
  listen           = true
  multihop         = false
  tcp_md5_key      = var.kubernetes_bgp_tcp_md5_key

  local {
    address = var.kubernetes_bgp.local_address
    role    = "ibgp"
  }

  remote {
    address = each.value.address
    as      = tostring(var.kubernetes_bgp.remote_asn)
  }

  input {
    accept_nlri               = var.kubernetes_bgp.service_vip_address_list
    filter                    = var.kubernetes_bgp.input_filter_chain
    limit_process_routes_ipv4 = 256
  }

  output {
    default_originate = "never"
  }

  lifecycle {
    # RouterOS 7.22.1 exposes these defaults through REST in a shape that the
    # Terraform provider cannot round-trip without sending unsupported fields.
    # Ignore them so Terraform can track the imported peers without rewriting
    # otherwise-correct BGP sessions on every plan.
    ignore_changes = [
      add_path_out,
      keepalive_time,
      nexthop_choice,
      local[0].port,
      remote[0].port,
    ]
  }

  depends_on = [
    routeros_ip_firewall_addr_list.kubernetes_service_vips,
    routeros_routing_filter_rule.kubernetes_bgp_in,
  ]
}
