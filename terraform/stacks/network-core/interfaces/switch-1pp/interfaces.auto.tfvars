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
# trunk and access behavior remains easy to review.
bridge_ports = {
  ether1 = {
    comment           = "defconf"
    pvid              = 10
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
    pvid              = 102
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
    pvid              = 100
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
    pvid              = 101
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether11 = {
    pvid              = 101
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
    pvid              = 100
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
    pvid              = 100
    frame_types       = "admit-all"
    ingress_filtering = true
  }
  ether17 = {
    comment           = "defconf"
    pvid              = 100
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
    pvid              = 100
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

# Keep bridge VLAN table entries explicit so imported VLAN forwarding intent
# does not depend on RouterOS live defaults.
bridge_vlans = {
  vlan100 = {
    vlan_ids = ["100"]
    tagged   = ["bridge", "sfp-sfpplus2"]
    untagged = ["ether6"]
  }
  vlan10 = {
    comment  = "VLAN10 - LAN"
    vlan_ids = ["10"]
    tagged   = ["bridge", "ether4", "sfp-sfpplus2"]
    untagged = []
  }
  vlan101 = {
    comment  = "Cameras"
    vlan_ids = ["101"]
    tagged   = ["bridge", "sfp-sfpplus2"]
    untagged = ["ether10"]
  }
  vlan102 = {
    comment  = "VLAN102"
    vlan_ids = ["102"]
    tagged   = ["sfp-sfpplus2"]
    untagged = ["ether4"]
  }
}

# Keep VLAN interfaces explicit in committed configuration so imported switch
# VLAN interfaces stay in the same state as the rest of the bridge topology.
vlan_interfaces = {
  vlan10 = {
    interface = "bridge"
    vlan_id   = 10
  }
  vlan100 = {
    interface = "bridge"
    vlan_id   = 100
  }
  vlan102 = {
    comment   = "AP MGMT"
    interface = "bridge"
    vlan_id   = 102
  }
}
