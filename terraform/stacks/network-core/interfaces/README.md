# Network Core Interfaces

This nested stack manages MikroTik interface topology and interface metadata
without expanding the parent `network-core` Terraform root into a catch-all
stack.

## Managed Devices

- `GW`: `10.1.100.1`
- `Switch 1PP`: `10.1.100.2`
- `Switch 1NP`: `10.1.100.3`

## Purpose

This root owns interface-focused concerns that deserve their own Terraform
state:

- gateway bridge configuration
- gateway bridge ports and VLAN filtering
- gateway VLAN interfaces
- gateway 6to4 tunnel interfaces
- physical interface descriptions on the gateway and both switches

The parent
[`network-core`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/README.md)
stack remains focused on committed device inventory and shared MikroTik
connection metadata. The nested
[`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md)
and
[`routing`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/routing/README.md)
roots remain the dedicated homes for gateway DHCP and routing concerns.

## Terraform Connection Model

This stack uses the official `terraform-routeros/routeros` provider with three
aliased provider configurations:

- `routeros.gw`
- `routeros.switch_1pp`
- `routeros.switch_1np`

The configured endpoint format for this repo is `https://<host>` backed by
RouterOS `www-ssl`.

## Local Configuration

The shared non-secret interface configuration is committed in
`interfaces.auto.tfvars`. Use `terraform.tfvars.example` only for local-only
overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` for local runs
  so `TF_VAR_mikrotik_password` and related values come from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured
- on self-hosted GitHub runners, provide `bws` and `BWS_ACCESS_TOKEN` so
  workflows can load `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` from Bitwarden

## Data Model

- Define physical interface descriptions through `ethernet_interfaces`, keyed
  first by device and then by RouterOS factory interface name.
- Define the gateway bridge separately through `gw_bridge` so the bridge object
  can be imported or updated independently from member ports.
- Define bridge membership and ingress behavior through `gw_bridge_ports` so
  access, trunk, and hybrid links stay explicit.
- Define bridge VLAN filtering entries through `gw_bridge_vlans` so tagged and
  untagged membership remains reviewable in version control.
- Define VLAN interfaces through `gw_vlan_interfaces` so interface comments and
  VLAN IDs stay aligned with the bridge design.
- Define 6to4 tunnels through `gw_6to4_interfaces` so tunnel MTU and remote
  endpoint changes stay in the same state as the rest of the interface
  topology.

## Rollout Notes

- This stack manages objects that often already exist on live RouterOS
  devices. The first rollout should import existing bridge, bridge port, bridge
  VLAN, VLAN interface, tunnel, and switch/gateway interface objects before any
  unattended apply is enabled.
- Until that initial import is completed, this stack should remain validate-only
  in CI even though it already commits non-secret desired state.
- Gateway bridge VLAN filtering depends on the intended port and VLAN inventory
  staying synchronized. Update bridge ports and bridge VLAN entries together in
  the same change whenever port roles change.

## Notes

- The current committed design uses one VLAN-aware bridge on `GW` named
  `bridge`.
- The current committed bridge model treats `ether1` and `sfp-sfpplus1` as
  tagged trunks, `ether2`, `ether3`, and `ether5` as access ports, and
  `ether4` and `ether6` as hybrid ports.
- Switch bridge and VLAN policy is intentionally deferred for now; this stack
  currently manages only switch physical interface descriptions.
- Treat `interfaces.auto.tfvars` as committed source-of-truth configuration for
  non-secret live interface values.
- Update this README when the interface data model, switch L2 scope, or nested
  stack layout changes.
