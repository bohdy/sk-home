# Network Core Interfaces: GW

This root manages `GW` interface topology and interface metadata in its own Terraform state so gateway changes do not share a blast radius with switch imports or switch VLAN edits.

## Managed Device

- `GW`: `10.1.100.1`

## Purpose

This root owns the gateway-specific interface concerns that should be planned and imported independently:

- physical interface descriptions
- the primary bridge and bridge ports
- bridge VLAN filtering entries
- VLAN interfaces
- the `sit1` 6to4 tunnel

## Local Configuration

The shared non-secret gateway interface configuration is committed in `interfaces.auto.tfvars`, while the shared managed VLAN catalog in [`../../vlans.yaml`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/vlans.yaml) now owns VLAN IDs, RouterOS interface names, and canonical comments. Use `terraform.tfvars.example` only for local-only overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` from the repo root for local runs so `TF_VAR_mikrotik_password` comes from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured

## Rollout Notes

- This root manages objects that already exist on the live gateway. Import the existing bridge, bridge ports, bridge VLANs, VLAN interfaces, and `sit1` before the first apply.
- Keep gateway bridge port VLAN membership and `device_vlans` interface ownership synchronized in the same change whenever a port role changes.
