resource "routeros_interface_bridge" "bridge" {
  provider       = routeros.gw
  name           = "bridge"
  comment        = "Primary LAN bridge"
  arp            = "enabled"
  admin_mac      = "18:FD:74:CF:73:F0"
  vlan_filtering = true
  fast_forward   = true
}
