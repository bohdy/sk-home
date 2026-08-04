# Enable IPFIX accounting on the WAN interface and export records to the
# in-cluster goflow2 collector. Timeouts stay at RouterOS defaults because no
# measured need has appeared yet; packet sampling stays off so records are a
# complete WAN view rather than a sampled subset. The provider resource always
# enables the traffic-flow system on create, so no separate enabled toggle is
# managed here.
import {
  to = routeros_ip_traffic_flow.wan
  id = "*0"
}

resource "routeros_ip_traffic_flow" "wan" {
  provider = routeros.gw

  interfaces = "ether8"
}

# The collector service VIP is the only export target. The version value uses
# the exact casing the provider validates ("IPFIX"); template refresh settings
# match the flow-collection design so goflow2 always has a fresh IPFIX
# template for its field mapping.
resource "routeros_ip_traffic_flow_target" "goflow2" {
  provider = routeros.gw

  dst_address         = "10.1.30.57"
  port                = 2055
  version             = "IPFIX"
  v9_template_refresh = 20
  v9_template_timeout = "5m"
  disabled            = false
}
