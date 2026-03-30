# Commit non-secret shared values here so Terraform and CI use the same
# Switch 1PP-focused source of truth for the live environment.
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
mikrotik_hosturl = "https://10.1.100.2"

# Reuse the shared automation account until per-device credentials are
# intentionally split out.
mikrotik_username = "terraform"

# Keep the transitional TLS setting explicit until certificate trust is fully
# established for the RouterOS provider.
mikrotik_insecure = true

# Keep physical interface descriptions committed by factory interface name so
# switch labels stay reviewable in version control.
ethernet_interfaces = {
  sfp-sfpplus1 = {
    comment = "Uplink to GW"
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
    comment           = "defconf"
    pvid_vlan         = "users"
    untagged_vlans    = ["users"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether2 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether3 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether4 = {
    comment           = "defconf"
    pvid_vlan         = "aps"
    tagged_vlans      = ["users"]
    untagged_vlans    = ["aps"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether5 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether6 = {
    comment           = "AP Tattoo"
    pvid_vlan         = "management"
    untagged_vlans    = ["management"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether7 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether8 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether9 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether10 = {
    comment           = "Camera - detsky pokoj"
    pvid_vlan         = "cameras"
    untagged_vlans    = ["cameras"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether11 = {
    pvid_vlan         = "cameras"
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether12 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether13 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether14 = {
    comment           = "defconf"
    pvid_vlan         = "management"
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether15 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether16 = {
    comment           = "defconf"
    pvid_vlan         = "management"
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether17 = {
    comment           = "defconf"
    pvid_vlan         = "management"
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus1 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus2 = {
    comment           = "defconf"
    pvid_vlan         = "management"
    tagged_vlans      = ["management", "users", "cameras", "aps"]
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus3 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  sfp-sfpplus4 = {
    comment           = "defconf"
    pvid              = 1
    frame_types       = "admit-all"
    ingress_filtering = true
  }
}

# Control which shared VLAN catalog entries get bridge VLAN table rows on
# Switch 1PP.
bridge_vlan_keys = ["users", "management", "cameras", "aps"]

# Keep per-device VLAN behavior explicit so the switch only instantiates the
# management VLAN interface it needs for its own L3 presence.
device_vlans = {
  management = {
    create_vlan_interface = true
  }
}
