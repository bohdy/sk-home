# Blocky is the only resolver advertised to every routed DHCP scope. It serves
# internal split DNS and forwards public recursion through the cluster DNS path.
dhcp_scopes = {
  server10 = {
    interface   = "vlan10"
    pool_name   = "pool-vlan10"
    range_start = "10.1.10.10"
    range_end   = "10.1.10.200"
    subnet      = "10.1.10.0/24"
    gateway     = "10.1.10.1"
    dns_servers = ["10.1.30.53"]
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
    dns_servers = ["10.1.30.53"]
    domain      = "sk.bohdal.name"
    lease_time  = "30m"
  }
  server101 = {
    interface   = "vlan101"
    pool_name   = "pool-vlan101"
    range_start = "10.1.101.10"
    range_end   = "10.1.101.250"
    subnet      = "10.1.101.0/24"
    gateway     = "10.1.101.1"
    dns_servers = ["10.1.30.53"]
    lease_time  = "30m"
    comment     = "VLAN101 - CAM"
  }
  server102 = {
    interface   = "vlan102"
    pool_name   = "pool-vlan102"
    range_start = "10.1.102.10"
    range_end   = "10.1.102.20"
    subnet      = "10.1.102.0/24"
    gateway     = "10.1.102.1"
    dns_servers = ["10.1.30.53"]
    domain      = "ap.sk.bohdal.name"
    lease_time  = "5m"
    add_arp     = true
    option_set  = "VLAN102"
    comment     = "VLAN102"
  }
}

# Keep static reservations in the DHCP stack so address ownership is reviewed
# alongside the scopes and client DNS settings that depend on it.
dhcp_reservations = {
  ap_1np = {
    server      = "server102"
    address     = "10.1.102.11"
    mac_address = "1C:6A:1B:92:32:B5"
    comment     = "AP 1NP"
  }
  u1_printer = {
    server      = "server10"
    address     = "10.1.10.200"
    mac_address = "40:D9:5A:7E:84:F6"
    comment     = "U1 Printer"
  }
  viktor_mcbp_m4 = {
    server      = "server10"
    address     = "10.1.10.10"
    mac_address = "56:50:34:15:CB:0B"
    comment     = "Viktor McBP M4"
  }
  camera_branka = {
    server      = "server101"
    address     = "10.1.101.20"
    mac_address = "EC:71:DB:99:0A:14"
    comment     = "Camera Branka"
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
  ap_1pp = {
    server      = "server102"
    address     = "10.1.102.10"
    mac_address = "94:2A:6F:C4:2F:24"
    comment     = "AP 1PP"
  }
  ap_temp = {
    server      = "server102"
    address     = "10.1.102.12"
    mac_address = "84:78:48:D6:B2:F4"
    comment     = "AP TEMP"
  }
  panda_breath = {
    server      = "server10"
    address     = "10.1.10.67"
    mac_address = "AC:EB:E6:92:DD:B0"
    client_id   = "1:ac:eb:e6:92:dd:b0"
    comment     = "Panda Breath"
  }
  brother_printer = {
    server      = "server10"
    address     = "10.1.10.13"
    mac_address = "3C:2A:F4:F4:B6:7F"
    client_id   = "1:3c:2a:f4:f4:b6:7f"
    comment     = "Brother printer"
  }
  apc_ups = {
    server      = "server10"
    address     = "10.1.10.43"
    mac_address = "60:45:2E:D8:B7:3D"
    client_id   = "1:60:45:2e:d8:b7:3d"
    comment     = "APC UPS"
  }
}
