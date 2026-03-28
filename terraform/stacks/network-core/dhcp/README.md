# Network Core DHCP

This nested stack manages DHCP on the MikroTik gateway without expanding the
parent `network-core` Terraform root into a catch-all stack.

## Managed Device

- `GW`: `10.1.100.1`

## Purpose

This root owns gateway DHCP concerns that deserve their own Terraform state:

- DHCP pools
- DHCP servers
- DHCP network settings
- static DHCP reservations
- DHCP options and option sets

The parent
[`network-core`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/README.md)
stack remains focused on router and switch foundations.

## Terraform Connection Model

This stack uses the official `terraform-routeros/routeros` provider with a
single aliased provider configuration:

- `routeros.gw`

The configured endpoint format for this repo is `https://<host>` backed by
RouterOS `www-ssl`.

## Local Configuration

The shared non-secret DHCP configuration is committed in `dhcp.auto.tfvars`.
Use `terraform.tfvars.example` only for local-only overrides or temporary
inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` for local runs
  so `TF_VAR_mikrotik_password` and related values come from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured
- on self-hosted GitHub runners, provide `bws` and `BWS_ACCESS_TOKEN` so
  workflows can load `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` from Bitwarden

## Data Model

- Define DHCP scopes through `dhcp_scopes` so pools, server bindings, and
  per-network options stay synchronized.
- Define static reservations through `dhcp_reservations` so committed IP-to-MAC
  ownership stays reviewable.
- Define vendor-specific DHCP options through `dhcp_option_sets` and reference
  them from a scope with `option_set`. Each option should carry an explicit
  RouterOS `name` so human-readable option objects do not depend on map keys.
- Keep reservation addresses within the intended subnet and avoid conflicts with
  unmanaged static addresses outside DHCP.

## Notes

- DHCP in this repo is modeled only on the `GW` device unless a later change
  explicitly extends it elsewhere.
- Treat `dhcp.auto.tfvars` as committed source-of-truth configuration for
  non-secret live DHCP values.
- Because this stack split moves existing DHCP objects out of the parent
  `network-core` state, the first rollout should migrate or import state rather
  than applying both roots naïvely and risking unintended deletes.
- Update this README when the DHCP data model, managed VLAN inventory, or
  nested stack layout changes.
