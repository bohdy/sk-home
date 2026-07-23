locals {
  # Use one source for every pool/server/network relationship so each managed
  # subnet remains internally consistent during future DHCP changes.
  dhcp_scopes = var.dhcp_scopes
}

resource "routeros_ip_pool" "scope" {
  provider = routeros.gw
  for_each = local.dhcp_scopes

  name    = each.value.pool_name
  ranges  = ["${each.value.range_start}-${each.value.range_end}"]
  comment = try(each.value.comment, null)
}

resource "routeros_ip_dhcp_server" "scope" {
  provider = routeros.gw
  for_each = local.dhcp_scopes

  name                      = each.key
  interface                 = each.value.interface
  address_pool              = routeros_ip_pool.scope[each.key].name
  lease_time                = each.value.lease_time
  add_arp                   = each.value.add_arp
  dynamic_lease_identifiers = "client-mac,client-id"
  comment                   = try(each.value.comment, null)
}

resource "routeros_ip_dhcp_server_network" "scope" {
  provider = routeros.gw
  for_each = local.dhcp_scopes

  address         = each.value.subnet
  gateway         = each.value.gateway
  dns_server      = each.value.dns_servers
  domain          = try(each.value.domain, null)
  dhcp_option_set = try(each.value.option_set, null)
  comment         = try(each.value.comment, null)
}

resource "routeros_ip_dhcp_server_option" "unifi_mgmt" {
  provider = routeros.gw

  name    = "Unifi MGMT"
  code    = 43
  value   = "0x01040a011e01"
  comment = "Unifi MGMT"
}

resource "routeros_ip_dhcp_server_option_sets" "vlan102" {
  provider = routeros.gw

  name    = "VLAN102"
  options = routeros_ip_dhcp_server_option.unifi_mgmt.name
}

resource "routeros_ip_dhcp_server_lease" "reservation" {
  provider = routeros.gw
  for_each = var.dhcp_reservations

  server       = each.value.server
  address      = each.value.address
  mac_address  = each.value.mac_address
  client_id    = try(each.value.client_id, null)
  block_access = false
  comment      = try(each.value.comment, null)
}
