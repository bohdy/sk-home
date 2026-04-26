vlans = {
  10 = {
    name       = "VLAN Users",
    tagged     = ["sfp-sfpplus1", "ether1", "ether6"],
    untagged   = ["ether2", "ether5"],
    ip_address = "10.1.10.1/24"
    iface_list = "LAN"
  },
  20 = {
    name       = "VLAN Servers",
    tagged     = ["sfp-sfpplus1", "ether4"],
    untagged   = [],
    ip_address = "10.1.20.1/24"
    iface_list = "LAN"
  },
  100 = {
    name       = "VLAN MGMT",
    tagged     = ["sfp-sfpplus1", "ether1"],
    untagged   = ["ether3", "ether4"],
    ip_address = "10.1.100.1/24"
    iface_list = "LAN"
  },
  101 = {
    name       = "VLAN Cameras",
    tagged     = ["sfp-sfpplus1"],
    untagged   = [],
    ip_address = "10.1.101.1/24"
  },
  102 = {
    name       = "VLAN APs",
    tagged     = ["sfp-sfpplus1", "ether1"],
    untagged   = ["ether6"],
    ip_address = "10.1.102.1/24"
  }
}
