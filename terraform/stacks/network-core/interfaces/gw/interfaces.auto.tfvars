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
# and hybrid behavior remain easy to review without repeating full bridge VLAN
# rows in separate data structures.
bridge_ports = {
  ether1 = {
    comment           = "Tagged trunk to SW-1NP"
    tagged_vlans      = ["management", "users", "aps"]
    frame_types       = "admit-only-vlan-tagged"
    ingress_filtering = true
  }
  ether2 = {
    comment           = "Access port for 1PP LAN"
    pvid_vlan         = "users"
    untagged_vlans    = ["users"]
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether3 = {
    comment           = "Access port for Synology management"
    pvid_vlan         = "management"
    untagged_vlans    = ["management"]
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether4 = {
    comment           = "Hybrid port for Proxmox"
    pvid_vlan         = "management"
    tagged_vlans      = ["servers"]
    untagged_vlans    = ["management"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether5 = {
    comment           = "Access port for 1PP MacMini"
    pvid_vlan         = "users"
    untagged_vlans    = ["users"]
    frame_types       = "admit-only-untagged-and-priority-tagged"
    ingress_filtering = true
  }
  ether6 = {
    comment           = "Hybrid port for 1PP AP"
    pvid_vlan         = "aps"
    tagged_vlans      = ["users"]
    untagged_vlans    = ["aps"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus1 = {
    comment           = "Tagged trunk to SW-1PP"
    tagged_vlans      = ["management", "users", "cameras", "aps"]
    frame_types       = "admit-only-vlan-tagged"
    ingress_filtering = true
  }
}

# Control which shared VLAN catalog entries get bridge VLAN table rows on the
# gateway.
bridge_vlan_keys = ["users", "servers", "management", "cameras", "aps"]

# Keep per-device VLAN behavior explicit so bridge comments and gateway-owned
# VLAN interfaces remain reviewable without redefining shared VLAN IDs or
# canonical comments.
device_vlans = {
  users = {
    create_vlan_interface = true
  }
  servers = {
    create_vlan_interface = true
  }
  management = {
    create_vlan_interface = true
  }
  cameras = {
    create_vlan_interface = true
  }
  aps = {
    create_vlan_interface = true
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

# Keep IPv4 gateway interface addresses committed so DHCP gateways, router ID
# reachability, and per-VLAN L3 ownership are managed in this root.
ipv4_interface_addresses = {
  vlan10-gateway = {
    interface = "vlan10"
    address   = "10.1.10.1/24"
    comment   = "Gateway IPv4 for VLAN Users"
  }
  vlan20-gateway = {
    interface = "vlan20"
    address   = "10.1.20.1/24"
    comment   = "Gateway IPv4 for VLAN Servers"
  }
  vlan100-gateway = {
    interface = "vlan100"
    address   = "10.1.100.1/24"
    comment   = "Gateway IPv4 for VLAN Management"
  }
  vlan101-gateway = {
    interface = "vlan101"
    address   = "10.1.101.1/24"
    comment   = "Gateway IPv4 for VLAN Cameras"
  }
  vlan102-gateway = {
    interface = "vlan102"
    address   = "10.1.102.1/24"
    comment   = "Gateway IPv4 for VLAN APs"
  }
}

# Keep IPv6 gateway interface addresses in committed data so dual-stack
# interface identity is managed in Terraform when values are defined.
ipv6_interface_addresses = {}
