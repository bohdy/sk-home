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

# Point Terraform at the RouterOS HTTPS endpoint backed by the `www-ssl`
# certificate so the provider can use the TLS-secured REST/API transport.
mikrotik_gw_hosturl = "https://10.1.100.1"

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
