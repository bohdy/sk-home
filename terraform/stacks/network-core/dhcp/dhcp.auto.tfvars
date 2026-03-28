# Commit non-secret shared values here so Terraform and CI use the same nested
# DHCP source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across DHCP resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the RouterOS HTTPS endpoint backed by `www-ssl` so the
# provider can use the TLS-secured REST/API transport for DHCP management.
mikrotik_gw_hosturl = "https://10.1.100.1"

# Use the dedicated automation user for RouterOS management.
mikrotik_username = "terraform"

# Skip TLS verification only while using self-signed certificates during
# bootstrap. Set this to false once trusted certificates are in place.
mikrotik_insecure = true

# Define DHCP scopes only on the gateway. Each scope maps the DHCP server, pool,
# reservation target, and per-network options from one shared declaration.
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
    option_set  = "vlan102"
  }
}

# Keep shared static reservations committed so address ownership stays visible
# alongside the rest of the DHCP desired state.
dhcp_reservations = {
  viktor_mcbp_m4 = {
    server      = "server10"
    address     = "10.1.10.10"
    mac_address = "56:50:34:15:cb:0b"
    comment     = "Viktor McBP M4"
  }
  macmini = {
    server      = "server10"
    address     = "10.1.10.20"
    mac_address = "A4:77:F3:01:0E:22"
    comment     = "MacMini"
  }
  kvm = {
    server      = "server10"
    address     = "10.1.10.70"
    mac_address = "94:83:C4:B7:27:C5"
    comment     = "KVM"
  }
  u1_printer = {
    server      = "server10"
    address     = "10.1.10.200"
    mac_address = "40:D9:5A:7E:84:F6"
    comment     = "U1 Printer"
  }
  camera_branka = {
    server      = "server101"
    address     = "10.1.101.20"
    mac_address = "EC:71:DB:99:0A:14"
    comment     = "Camera Branka"
  }
  ap_1pp = {
    server      = "server102"
    address     = "10.1.102.10"
    mac_address = "94:2A:6F:C4:2F:24"
    comment     = "AP 1PP"
  }
  ap_1np = {
    server      = "server102"
    address     = "10.1.102.11"
    mac_address = "1C:6A:1B:92:32:B5"
    comment     = "AP 1NP"
  }
  ap_temp = {
    server      = "server102"
    address     = "10.1.102.12"
    mac_address = "84:78:48:D6:B2:F4"
    comment     = "AP TEMP"
  }
}

# Keep vendor-specific DHCP options grouped into named sets so one scope can
# opt into a bundle without duplicating raw option values.
dhcp_option_sets = {
  vlan102 = {
    name = "VLAN102"
    options = {
      unifi_mgmt = {
        name    = "Unifi MGMT"
        code    = 43
        value   = "0x01040a011e01"
        comment = "Unifi MGMT"
      }
    }
  }
}
