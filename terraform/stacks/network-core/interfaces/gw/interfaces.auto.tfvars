# Commit non-secret shared values here so Terraform and CI use the same
# gateway-focused source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across gateway resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the RouterOS HTTPS endpoint backed by `www-ssl`
# certificates so the provider can use the TLS-secured REST/API transport.
mikrotik_hosturl = "https://10.1.100.1"

# Reuse the shared automation account until per-device credentials are
# intentionally split out.
mikrotik_username = "terraform"

# Keep the transitional TLS setting explicit until certificate trust is fully
# established for the RouterOS provider.
mikrotik_insecure = true

# Keep physical interface descriptions committed by factory interface name so
# gateway labels stay reviewable in version control.
ethernet_interfaces = {
  ether1 = {
    comment = "Downlink to SW-1NP"
  }
  ether2 = {
    comment = "1PP LAN"
  }
  ether3 = {
    comment = "Synology NAS"
  }
  ether4 = {
    comment = "Proxmox"
  }
  ether5 = {
    comment = "1PP MacMini"
  }
  ether6 = {
    comment = "1PP AP"
  }
  ether7 = {
    comment = "-empty-"
  }
  ether8 = {
    comment = "WAN (to antenna)"
  }
  sfp-sfpplus1 = {
    comment = "Downlink to SW-1PP"
  }
}

# Keep the gateway bridge definition explicit so VLAN filtering can be managed
# without relying on implicit RouterOS defaults.
bridge = {
  name           = "bridge"
  comment        = "Primary LAN bridge"
  vlan_filtering = true
}

# Keep bridge port membership keyed by physical interface name so access, trunk,
# and hybrid behavior remains easy to review.
bridge_ports = {
  ether1 = {
    comment           = "Tagged trunk to SW-1NP"
    frame_types       = "admit-only-vlan-tagged"
    ingress_filtering = true
  }
  ether2 = {
    comment           = "Access port for 1PP LAN"
    pvid              = 10
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether3 = {
    comment           = "Access port for Synology management"
    pvid              = 100
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether4 = {
    comment           = "Hybrid port for Proxmox"
    pvid              = 100
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether5 = {
    comment           = "Access port for 1PP MacMini"
    pvid              = 10
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether6 = {
    comment           = "Hybrid port for 1PP AP"
    pvid              = 102
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus1 = {
    comment           = "Tagged trunk to SW-1PP"
    frame_types       = "admit-only-vlan-tagged"
    ingress_filtering = true
  }
}

# Keep bridge VLAN table entries explicit so tagged and untagged forwarding
# intent does not depend on RouterOS live defaults.
bridge_vlans = {
  vlan10 = {
    comment  = "VLAN Users"
    vlan_ids = ["10"]
    tagged   = ["bridge", "ether1", "ether6", "sfp-sfpplus1"]
    untagged = ["ether2", "ether5"]
  }
  vlan20 = {
    comment  = "VLAN Servers"
    vlan_ids = ["20"]
    tagged   = ["bridge", "ether4"]
    untagged = []
  }
  vlan100 = {
    comment  = "VLAN Management"
    vlan_ids = ["100"]
    tagged   = ["bridge", "ether1", "sfp-sfpplus1"]
    untagged = ["ether3", "ether4"]
  }
  vlan101 = {
    comment  = "VLAN Cameras"
    vlan_ids = ["101"]
    tagged   = ["bridge", "sfp-sfpplus1"]
    untagged = []
  }
  vlan102 = {
    comment  = "VLAN APs"
    vlan_ids = ["102"]
    tagged   = ["bridge", "ether1", "sfp-sfpplus1"]
    untagged = ["ether6"]
  }
}

# Keep VLAN interfaces explicit on the gateway bridge so interface comments and
# RouterOS VLAN IDs stay committed together.
vlan_interfaces = {
  vlan10 = {
    comment   = "VLAN Users"
    interface = "bridge"
    vlan_id   = 10
  }
  vlan20 = {
    comment   = "VLAN Servers"
    interface = "bridge"
    vlan_id   = 20
  }
  vlan100 = {
    comment   = "VLAN Management"
    interface = "bridge"
    vlan_id   = 100
  }
  vlan101 = {
    comment   = "VLAN Cameras"
    interface = "bridge"
    vlan_id   = 101
  }
  vlan102 = {
    comment   = "VLAN APs"
    interface = "bridge"
    vlan_id   = 102
  }
}

# Keep 6to4 tunnel settings explicit in committed configuration so the HE.net
# tunnel can evolve in the same stack as the rest of the interface topology.
six_to_four_interfaces = {
  sit1 = {
    comment        = "HE.net IPv6 broker"
    mtu            = "1280"
    local_address  = "10.21.162.142"
    remote_address = "216.66.86.122"
    clamp_tcp_mss  = true
  }
}
