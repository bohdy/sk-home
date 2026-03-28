# Network Core Interfaces: Switch 1NP

This root manages `Switch 1NP` interface topology and metadata in its own Terraform state so switch onboarding, imports, and VLAN edits do not share a blast radius with the gateway or the other switch.

## Managed Device

- `Switch 1NP`: `10.1.100.3`

## Purpose

This root owns the Switch 1NP interface concerns that should be planned and imported independently:

- physical interface descriptions
- the primary bridge and bridge ports
- bridge VLAN filtering entries
- bridge-backed VLAN interfaces

## Local Configuration

The shared non-secret Switch 1NP interface configuration is committed in `interfaces.auto.tfvars`. Use `terraform.tfvars.example` only for local-only overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` from the repo root for local runs so `TF_VAR_mikrotik_password` comes from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured

## Rollout Notes

- This root manages objects that already exist on the live switch. Import the existing bridge, bridge ports, bridge VLANs, and VLAN interfaces before the first apply.
- Dynamic VLAN rows added by RouterOS should stay out of committed desired state unless the provider can manage them directly.
