# Network Core Interfaces: Switch 1PP

This root manages `Switch 1PP` interface topology and metadata in its own Terraform state so switch onboarding, imports, and VLAN edits do not share a blast radius with the gateway or the other switch.

## Managed Device

- `Switch 1PP`: `10.1.100.2`

## Purpose

This root owns the Switch 1PP interface concerns that should be planned and imported independently:

- physical interface descriptions
- the primary bridge and bridge ports
- bridge VLAN filtering entries
- the management VLAN interface used for the switch's own IP presence

## Local Configuration

The shared non-secret Switch 1PP interface configuration is committed in `interfaces.auto.tfvars`, while the shared managed VLAN catalog in [`../../vlans.yaml`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/vlans.yaml) now owns VLAN IDs, RouterOS interface names, and canonical comments. Use `terraform.tfvars.example` only for local-only overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` from the repo root for local runs so `TF_VAR_mikrotik_password` comes from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured

## Rollout Notes

- This root manages objects that already exist on the live switch. Import the existing bridge, bridge ports, bridge VLANs, and VLAN interfaces before the first apply.
- Keep Switch 1PP tagged and untagged port membership in `bridge_ports`, derive bridge VLAN rows from the shared catalog, and use `device_vlans` only for VLAN interfaces the switch itself needs.
- On Switch 1PP, that means `device_vlans` should normally create only the management VLAN interface and leave user, camera, and AP VLAN interfaces to the gateway.
- Dynamic VLAN rows added by RouterOS should stay out of committed desired state unless the provider can manage them directly.
