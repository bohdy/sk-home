# Commit non-secret shared values here so Terraform and CI use the same routing
# source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across gateway routing
# resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the live RouterOS REST endpoint for the gateway.
# The current GW API is reachable on plain HTTP while `www-ssl` is unavailable.
mikrotik_gw_hosturl = "http://10.1.100.1"

# Reuse the gateway automation account already used by the other MikroTik
# stacks so CI and local workflows share one credential model.
mikrotik_username = "terraform"

# Keep the current TLS bypass enabled until the gateway certificate chain is
# fully trusted by the Terraform execution environment.
mikrotik_insecure = true

# The RouterOS provider still requires a gateway field even when a route is a
# blackhole and RouterOS itself does not use a next hop for that route type.
blackhole_gateway_placeholder = ""

# Blackhole private IPv4 space that should never be forwarded through the
# gateway routing table.
ipv4_static_routes = {
  private-10-8 = {
    dst_address = "10.0.0.0/8"
    comment     = "Blackhole RFC1918 10.0.0.0/8"
  }
  private-10-1-16 = {
    dst_address = "10.1.0.0/16"
    comment     = "Blackhole home aggregate 10.1.0.0/16"
  }
  private-172-16-12 = {
    dst_address = "172.16.0.0/12"
    comment     = "Blackhole RFC1918 172.16.0.0/12"
  }
  private-192-168-16 = {
    dst_address = "192.168.0.0/16"
    comment     = "Blackhole RFC1918 192.168.0.0/16"
  }
}

# Blackhole committed IPv6 prefixes that should terminate on the gateway when
# no more specific route exists.
ipv6_static_routes = {
  routed-2001-470-59cf-48 = {
    dst_address = "2001:470:59cf::/48"
    comment     = "Blackhole delegated IPv6 aggregate 2001:470:59cf::/48"
  }
  routed-2a02-768-e915-a28e-64 = {
    dst_address = "2a02:768:e915:a28e::/64"
    comment     = "Blackhole routed IPv6 prefix 2a02:768:e915:a28e::/64"
  }
}

# Keep the live GW BGP instance inventory committed so RouterOS routing identity
# stays reviewable and importable from one source of truth.
bgp_instances = {
  "bgp-instance" = {
    as            = "65001"
    router_id     = "10.1.20.1"
    routing_table = "main"
    vrf           = "main"
  }
}

# Keep reusable BGP templates committed separately so session groups can inherit
# shared behavior without repeating all template fields per connection.
bgp_templates = {
  default = {
    as       = "65001"
    disabled = false
  }
  "k8s-cluster" = {
    as             = "65001"
    disabled       = false
    keepalive_time = "30s"
    hold_time      = "1m30s"
    multihop       = false
    routing_table  = "main"
  }
}

# Mirror the live GW BGP connection set exactly so imported session state can
# converge before any later cleanup or policy redesign.
bgp_connections = {
  "bgp-sh-v4" = {
    as               = "65001"
    disabled         = false
    instance         = "bgp-instance"
    routing_table    = "main"
    vrf              = "main"
    address_families = "ip,ipv6"
    local = {
      role = "ebgp"
    }
    output = {
      as_override                    = false
      default_prepend                = 0
      filter_chain                   = "SH_Out_v4"
      keep_sent_attributes           = false
      no_client_to_client_reflection = false
      no_early_cut                   = false
      redistribute                   = "connected,static"
      remove_private_as              = false
    }
    remote = {
      address = "169.254.0.2"
      as      = "65002"
    }
  }
  "bgp-sh-v6" = {
    as               = "65001"
    disabled         = true
    instance         = "bgp-instance"
    routing_table    = "main"
    vrf              = "main"
    address_families = "ipv6"
    local = {
      role    = "ebgp"
      address = "fd00:12::1"
    }
    output = {
      as_override                    = false
      default_prepend                = 0
      filter_chain                   = "SH_Out_v6"
      keep_sent_attributes           = false
      no_client_to_client_reflection = false
      no_early_cut                   = false
      redistribute                   = "connected"
      remove_private_as              = false
    }
    remote = {
      address = "fd00:12::2"
      as      = "65002"
    }
  }
  "bgp-sk-k3s-master01" = {
    as             = "65001"
    comment        = "legacy-k8s-connection"
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role = "ibgp"
    }
    remote = {
      address = "10.1.20.101"
      as      = "65001"
    }
  }
  "bgp-sk-k3s-worker01" = {
    as             = "65001"
    comment        = "k3s-connection"
    connect        = true
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    multihop       = false
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role    = "ibgp"
      address = "10.1.20.1"
    }
    output = {
      as_override                    = false
      default_originate              = "always"
      default_prepend                = 0
      keep_sent_attributes           = false
      no_client_to_client_reflection = false
      no_early_cut                   = false
      remove_private_as              = false
    }
    remote = {
      address = "10.1.20.102"
      as      = "65001"
    }
  }
  "bgp-sk-k3s-worker02" = {
    as             = "65001"
    comment        = "legacy-k8s-connection"
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    multihop       = false
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role = "ibgp"
    }
    remote = {
      address = "10.1.20.103"
      as      = "65001"
    }
  }
  # Keep parallel iBGP sessions to the new k3s cluster active during
  # application migration so traffic can shift incrementally before legacy peer
  # cleanup.
  "bgp-sk-k3s-new-server01" = {
    as             = "65001"
    comment        = "k3s-parallel-cutover"
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role = "ibgp"
    }
    remote = {
      address = "10.1.20.11"
      as      = "65001"
    }
  }
  "bgp-sk-k3s-new-worker01" = {
    as             = "65001"
    comment        = "k3s-parallel-cutover"
    connect        = true
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    multihop       = false
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role    = "ibgp"
      address = "10.1.20.1"
    }
    output = {
      as_override                    = false
      default_originate              = "always"
      default_prepend                = 0
      keep_sent_attributes           = false
      no_client_to_client_reflection = false
      no_early_cut                   = false
      remove_private_as              = false
    }
    remote = {
      address = "10.1.20.12"
      as      = "65001"
    }
  }
  "bgp-sk-k3s-new-worker02" = {
    as             = "65001"
    comment        = "k3s-parallel-cutover"
    disabled       = false
    hold_time      = "1m30s"
    instance       = "bgp-instance"
    keepalive_time = "30s"
    multihop       = false
    routing_table  = "main"
    vrf            = "main"
    templates      = ["k8s-cluster"]
    local = {
      role = "ibgp"
    }
    remote = {
      address = "10.1.20.13"
      as      = "65001"
    }
  }
}

# Keep the live GW routing export filters committed as explicit policy rules so
# BGP advertisements remain reviewable in version control.
routing_filter_rules = {
  "sh-out-010-accept-home-v4" = {
    chain    = "SH_Out"
    disabled = false
    rule     = "if (dst in 10.1.0.0/16) { accept; }"
  }
  "sh-out-020-accept-home-v6" = {
    chain    = "SH_Out"
    disabled = false
    rule     = "if (dst in 2001:470:59cf::/48 && dst-len in 48-64) {accept;}"
  }
  "sh-out-999-reject" = {
    chain    = "SH_Out"
    disabled = false
    rule     = "reject;"
  }
  "sh-out-v4-010-accept-home-v4" = {
    chain    = "SH_Out_v4"
    disabled = false
    rule     = "if (dst in 10.1.0.0/16) { accept; }"
  }
  "sh-out-v4-999-reject" = {
    chain    = "SH_Out_v4"
    disabled = false
    rule     = "reject"
  }
  "sh-out-v6-010-accept-home-v6" = {
    chain    = "SH_Out_v6"
    disabled = false
    rule     = <<-EOT
      if (dst in 2001:470:59cf::/48 && dst-len in 48-64) {accept;}
    EOT
  }
  "sh-out-v6-999-reject" = {
    chain    = "SH_Out_v6"
    disabled = false
    rule     = "reject;"
  }
}
