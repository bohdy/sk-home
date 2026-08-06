# Enable IPFIX accounting on the WAN interface and every routed LAN VLAN, then
# export records to the in-cluster goflow2 collector. The VLAN interfaces are
# derived from the same inventory that creates their gateway addresses. Do not
# add the bridge here: same-VLAN switching is outside this routed-flow scope and
# an overlapping bridge selector would make duplicate accounting more likely.
locals {
  traffic_flow_interfaces = concat(
    ["ether8"],
    [
      for vlan_id in sort(keys(var.vlans)) : "vlan${vlan_id}"
      if var.vlans[vlan_id].ip_address != null
    ]
  )
}

# Timeouts stay at RouterOS defaults because no measured need has appeared yet;
# packet sampling stays off so records are a complete view rather than a
# sampled subset. Traffic-flow is a RouterOS singleton, so this updates the
# existing configuration idempotently.
resource "routeros_ip_traffic_flow" "wan" {
  provider = routeros.gw

  interfaces = join(",", local.traffic_flow_interfaces)
}

# The collector target uses the worker node's physical address and the fixed
# NodePort (31236) instead of the Cilium VIP. Cilium VXLAN forwarding from CP
# nodes to workers is unreliable in the current Talos veth Cilium mode, and
# the NodePort on the pod's own node routes directly without crossing the
# overlay. The version value must pass the provider's case-sensitive
# validation ("IPFIX") while RouterOS expects lowercase "ipfix"; the
# lifecycle ignore keeps the manually-set ipfix version from being reverted.
resource "routeros_ip_traffic_flow_target" "goflow2" {
  provider = routeros.gw

  dst_address         = var.kubernetes_bgp.nodes.worker1.address
  port                = 31236
  version             = "9"
  v9_template_refresh = 20
  v9_template_timeout = "5m"
  disabled            = false

  lifecycle {
    ignore_changes = [version]
  }
}
