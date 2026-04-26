vlans = {
  10 = {
    name     = "VLAN Users",
    tagged   = ["sfp-sfpplus1", "ether1", "ether6"],
    untagged = ["ether2", "ether5"]
  },
  20 = {
    name     = "VLAN Servers",
    tagged   = ["sfp-sfpplus1", "ether4"],
    untagged = []
  },
  100 = {
    name     = "VLAN MGMT",
    tagged   = ["sfp-sfpplus1", "ether1"],
    untagged = ["ether3", "ether4"]
  },
  101 = {
    name     = "VLAN Cameras",
    tagged   = ["sfp-sfpplus1"],
    untagged = []
  },
  102 = {
    name     = "VLAN APs",
    tagged   = ["sfp-sfpplus1", "ether1"],
    untagged = ["ether6"]
  }
}
