# Adopt the two verified WireGuard interfaces without taking ownership of their
# private keys. The provider keeps those values in sensitive state after import,
# while lifecycle ignores prevent a missing source value from rotating them.
resource "routeros_interface_wireguard" "managed" {
  provider = routeros.gw
  for_each = var.wireguard_interfaces

  name        = each.value.name
  listen_port = each.value.listen_port
  mtu         = each.value.mtu
  comment     = each.value.comment

  lifecycle {
    ignore_changes = [private_key]
  }
}

# Peer public configuration is ordinary desired state; private and preshared
# keys remain provider-managed sensitive state and are never committed here.
resource "routeros_interface_wireguard_peer" "managed" {
  provider = routeros.gw
  for_each = var.wireguard_peers

  interface            = each.value.interface
  public_key           = each.value.public_key
  allowed_address      = each.value.allowed_address
  endpoint_address     = each.value.endpoint_address
  endpoint_port        = each.value.endpoint_port
  persistent_keepalive = each.value.persistent_keepalive
  disabled             = each.value.disabled
  comment              = each.value.comment

  depends_on = [routeros_interface_wireguard.managed]

  lifecycle {
    ignore_changes = [private_key, preshared_key]
  }
}

# These imports are temporary state-migration scaffolding. Remove them after
# the targeted no-destroy adoption apply and a clean follow-up plan.
import {
  to = routeros_interface_wireguard.managed["roadwarrior"]
  id = "*1A"
}

import {
  to = routeros_interface_wireguard.managed["site_to_site"]
  id = "*14"
}

import {
  to = routeros_interface_wireguard_peer.managed["site_to_site_sh"]
  id = "*4"
}

import {
  to = routeros_interface_wireguard_peer.managed["site_to_site_ck"]
  id = "*5"
}

import {
  to = routeros_interface_wireguard_peer.managed["roadwarrior_viktor"]
  id = "*6"
}

import {
  to = routeros_interface_wireguard_peer.managed["roadwarrior_ipad"]
  id = "*8"
}
