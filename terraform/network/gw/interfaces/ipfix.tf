# Enable IPFIX accounting on the WAN interface and export records to the
# in-cluster goflow2 collector. Timeouts stay at RouterOS defaults because no
# measured need has appeared yet; packet sampling stays off so records are a
# complete WAN view rather than a sampled subset. The traffic-flow system is a
# RouterOS singleton, so the apply updates the existing resource idempotently.
resource "routeros_ip_traffic_flow" "wan" {
  provider = routeros.gw

  interfaces = "ether8"
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
