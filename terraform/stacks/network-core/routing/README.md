# Network Core Routing

This nested stack manages gateway routing on the MikroTik `GW` device without expanding the parent `network-core` Terraform root into a catch-all stack.

## Managed Device

- `GW`: `10.1.100.1`

## Purpose

This root owns gateway routing concerns that deserve their own Terraform state:

- static IPv4 routes
- static IPv6 routes
- future BGP routing configuration

The parent [`network-core`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/README.md) stack remains focused on router and switch foundations.

## Terraform Connection Model

This stack uses the official `terraform-routeros/routeros` provider with a single aliased provider configuration:

- `routeros.gw`

The configured endpoint format for this repo is `https://<host>` backed by RouterOS `www-ssl`.

## Local Configuration

The shared non-secret routing configuration is committed in `routing.auto.tfvars`. Use `terraform.tfvars.example` only for local-only overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` for local runs so `TF_VAR_mikrotik_password` and related values come from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured
- on self-hosted GitHub runners, provide `bws` and `BWS_ACCESS_TOKEN` so workflows can load `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` from Bitwarden

## Data Model

- Define IPv4 static routes through `ipv4_static_routes` so committed destination prefixes, route state, and comments stay reviewable.
- Define IPv6 static routes through `ipv6_static_routes` because the RouterOS provider manages IPv6 routes through a dedicated Terraform resource.
- Blackhole routes currently use the committed `blackhole_gateway_placeholder` compatibility value because the provider still requires a gateway attribute even though RouterOS blackhole routes do not use a next hop.
- Keep this stack as the future home for BGP routing work, but add BGP resources only when there is committed BGP intent to manage.

## Notes

- Routing in this repo is modeled only on the `GW` device unless a later change explicitly extends it elsewhere.
- Treat `routing.auto.tfvars` as committed source-of-truth configuration for non-secret live routing values.
- Validate one IPv4 and one IPv6 blackhole route against the current provider behavior before treating the blackhole compatibility placeholder as proven safe for unattended rollout.
- Update this README when the routing data model, BGP scope, or nested stack layout changes.
