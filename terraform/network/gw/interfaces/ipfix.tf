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

# The collector target uses the reserved Cilium LoadBalancer VIP so the gateway
# does not depend on one worker's physical address. The service uses Cluster
# traffic policy and the verified BGP route to reach the active collector pod.
# The version value must pass the provider's case-sensitive validation ("IPFIX")
# while RouterOS expects lowercase "ipfix"; the lifecycle ignore keeps the
# manually-set ipfix version from being reverted.
resource "routeros_ip_traffic_flow_target" "goflow2" {
  provider = routeros.gw

  dst_address         = var.kubernetes_flow_collector_vip
  port                = 2055
  version             = "9"
  v9_template_refresh = 20
  v9_template_timeout = "5m"
  disabled            = false

  lifecycle {
    ignore_changes = [version]
  }
}
