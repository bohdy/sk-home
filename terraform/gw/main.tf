resource "routeros_interface_bridge" "bridge" {
  provider       = routeros.gw
  name           = "bridge"
  comment        = "Primary LAN bridge"
  arp            = "enabled"
  admin_mac      = "18:FD:74:CF:73:F0"
  vlan_filtering = true
  fast_forward   = true
}

resource "routeros_interface_ethernet" "ether1" {
  provider     = routeros.gw
  factory_name = "ether1"
  name         = "ether1"
  comment      = "Downlink to SW-1NP"
}

resource "routeros_interface_ethernet" "ether2" {
  provider     = routeros.gw
  factory_name = "ether2"
  name         = "ether2"
  comment      = "Downlink to SW-1PP"
}

resource "routeros_interface_ethernet" "ether3" {
  provider     = routeros.gw
  factory_name = "ether3"
  name         = "ether3"
  comment      = "Synology NAS"
}

resource "routeros_interface_ethernet" "ether4" {
  provider     = routeros.gw
  factory_name = "ether4"
  name         = "ether4"
  comment      = "Proxmox"
}

resource "routeros_interface_ethernet" "ether5" {
  provider     = routeros.gw
  factory_name = "ether5"
  name         = "ether5"
  comment      = "1PP MacMini"
}

resource "routeros_interface_ethernet" "ether6" {
  provider     = routeros.gw
  factory_name = "ether6"
  name         = "ether6"
  comment      = "1PP AP"
}

resource "routeros_interface_ethernet" "ether8" {
  provider     = routeros.gw
  factory_name = "ether8"
  name         = "ether8"
  comment      = "WAN (to antenna)"
}

resource "routeros_interface_bridge_port" "bridge_port_ethernet" {
  for_each  = var.interfaces
  provider  = routeros.gw
  bridge    = routeros_interface_bridge.bridge.name
  interface = each.value.name
  comment   = each.value.name
  pvid      = each.value.pvid
}

resource "routeros_interface_ethernet" "ethernet" {
  for_each     = var.interfaces
  provider     = routeros.gw
  factory_name = each.value.name
  name         = each.value.name
  comment      = each.value.comment
}

resource "routeros_interface_bridge_vlan" "bridge_vlan" {
  for_each = var.vlans
  provider = routeros.gw
  vlan_ids = [tonumber(each.key)]
  bridge   = routeros_interface_bridge.bridge.name
  tagged   = setunion([routeros_interface_bridge.bridge.name], each.value.tagged)
  untagged = each.value.untagged
  comment  = each.value.name
}
