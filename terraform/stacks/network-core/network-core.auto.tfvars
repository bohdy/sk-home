# Commit non-secret shared values here so Terraform and CI use the same
# network-core source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across network-core resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the RouterOS API-SSL endpoints for each MikroTik device.
mikrotik_gw_hosturl         = "apis://10.1.100.1:8729"
mikrotik_switch_1pp_hosturl = "apis://10.1.100.2:8729"
mikrotik_switch_1np_hosturl = "apis://10.1.100.3:8729"

# Use the dedicated automation user for RouterOS management.
mikrotik_username = "terraform"

# Skip TLS verification only while using self-signed certificates during
# bootstrap. Set this to false once trusted certificates are in place.
mikrotik_insecure = true

# Define DHCP scopes only on the gateway. Each scope maps the DHCP server, pool,
# and per-network options from one shared declaration.
dhcp_scopes = {
  server10 = {
    interface   = "vlan10"
    pool_name   = "pool-vlan10"
    range_start = "10.1.10.10"
    range_end   = "10.1.10.200"
    subnet      = "10.1.10.0/24"
    gateway     = "10.1.10.1"
    dns_servers = ["10.1.30.255"]
    domain      = "sk.bohdal.name"
    lease_time  = "30m"
  }
  server100 = {
    interface   = "vlan100"
    pool_name   = "pool-vlan100"
    range_start = "10.1.100.10"
    range_end   = "10.1.100.250"
    subnet      = "10.1.100.0/24"
    gateway     = "10.1.100.1"
    dns_servers = ["86.54.11.13"]
    domain      = "sk.bohdal.name"
    lease_time  = "30m"
  }
  server101 = {
    comment     = "VLAN101 - CAM"
    interface   = "vlan101"
    pool_name   = "pool-vlan101"
    range_start = "10.1.101.10"
    range_end   = "10.1.101.250"
    subnet      = "10.1.101.0/24"
    gateway     = "10.1.101.1"
    lease_time  = "30m"
  }
  server102 = {
    comment     = "VLAN102"
    interface   = "vlan102"
    pool_name   = "pool-vlan102"
    range_start = "10.1.102.10"
    range_end   = "10.1.102.20"
    subnet      = "10.1.102.0/24"
    gateway     = "10.1.102.1"
    dns_servers = ["8.8.8.8"]
    domain      = "ap.sk.bohdal.name"
    lease_time  = "5m"
    add_arp     = true
  }
}
