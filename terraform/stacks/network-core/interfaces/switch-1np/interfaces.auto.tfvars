# Commit non-secret shared values here so Terraform and CI use the same
# Switch 1NP-focused source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across switch resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the RouterOS HTTPS endpoint backed by `www-ssl`
# certificates so the provider can use the TLS-secured REST/API transport.
mikrotik_hosturl = "https://10.1.100.3"

# Reuse the shared automation account until per-device credentials are
# intentionally split out.
mikrotik_username = "terraform"

# Keep the transitional TLS setting explicit until certificate trust is fully
# established for the RouterOS provider.
mikrotik_insecure = true

# Keep physical interface descriptions committed by factory interface name so
# switch labels stay reviewable in version control.
ethernet_interfaces = {
  ether1 = {
    comment = "Uplink to GW"
  }
  ether5 = {
    comment = "1NP AP"
  }
}

# Keep the switch bridge definition explicit so imported VLAN filtering stays
# reviewable in version control.
bridge = {
  name           = "bridge"
  comment        = "defconf"
  vlan_filtering = true
}

# Keep bridge port membership keyed by physical interface name so imported
# trunk, access, and hybrid behavior remain easy to review without repeating
# full bridge VLAN rows in separate data structures.
bridge_ports = {
  ether1 = {
    pvid_vlan         = "management"
    tagged_vlans      = ["management", "users", "aps"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether2 = {
    comment           = "defconf"
    pvid_vlan         = "users"
    untagged_vlans    = ["management"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether3 = {
    comment           = "defconf"
    pvid_vlan         = "users"
    untagged_vlans    = ["users"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether4 = {
    comment           = "defconf"
    pvid_vlan         = "users"
    untagged_vlans    = ["users"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether5 = {
    comment           = "defconf"
    pvid_vlan         = "aps"
    tagged_vlans      = ["users"]
    untagged_vlans    = ["management", "aps"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp1 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
}

# Keep per-device VLAN behavior explicit so switch-owned VLAN interfaces remain
# reviewable without redefining shared VLAN IDs or canonical comments.
device_vlans = {
  management = {
    create_vlan_interface = true
  }
  users = {}
  aps = {
    create_vlan_interface = true
  }
}
