# Enable IPFIX accounting on the WAN interface and export records to the
# in-cluster goflow2 collector. Timeouts stay at RouterOS defaults because no
# measured need has appeared yet; packet sampling stays off so records are a
# complete WAN view rather than a sampled subset. The traffic-flow system is a
# RouterOS singleton, so the apply updates the existing resource idempotently.
resource "routeros_ip_traffic_flow" "wan" {
  provider = routeros.gw

  interfaces = "ether8"
}

# The collector service VIP is the only export target. The provider's
# ValidateFunc only accepts uppercase "IPFIX" while the RouterOS REST API
# expects lowercase "ipfix", so the version field is managed manually on the
# gateway while Tofu owns everything else. After the initial apply, set
# version=ipfix on the gateway: /ip traffic-flow target set [find] version=ipfix
resource "routeros_ip_traffic_flow_target" "goflow2" {
  provider = routeros.gw

  dst_address         = "10.1.30.57"
  port                = 2055
  version             = "9"
  v9_template_refresh = 20
  v9_template_timeout = "5m"
  disabled            = false

  lifecycle {
    ignore_changes = [version]
  }
}
