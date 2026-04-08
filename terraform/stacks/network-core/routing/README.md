# Network Core Routing

This nested stack manages gateway routing on the MikroTik `GW` device without expanding the parent `network-core` Terraform root into a catch-all stack.

## Managed Device

- `GW`: `10.1.100.1`

## Purpose

This root owns gateway routing concerns that deserve their own Terraform state:

- static IPv4 routes
- static IPv6 routes
- BGP instances, templates, sessions, and routing filters

The parent [`network-core`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/README.md) stack remains focused on router and switch foundations.

## Terraform Connection Model

This stack uses the official `terraform-routeros/routeros` provider with a single aliased provider configuration:

- `routeros.gw`

The configured endpoint format for this stack follows the live GW API service. Today the committed gateway endpoint uses `http://<host>` because `www-ssl` on the GW is currently unavailable.

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
- Define BGP instances through `bgp_instances` so shared RouterOS BGP identity stays committed independently from peer sessions.
- Define reusable peer defaults through `bgp_templates` so connection groups can inherit shared settings without repeating them per session.
- Define live BGP sessions through `bgp_connections`, including explicit `local`, `remote`, and `output` blocks so imported RouterOS state can converge without hidden provider defaults.
- Set `bgp_connections.keepalive_time` and `bgp_connections.hold_time` explicitly for peers that must use non-default BGP timers; this keeps hold/keepalive behavior convergent after import.
- Define BGP routing policy through `routing_filter_rules` so export filters remain reviewable even though RouterOS filter rules are not named objects.
- Blackhole routes currently use the committed `blackhole_gateway_placeholder` compatibility value because the provider still requires a gateway attribute even though RouterOS blackhole routes do not use a next hop.
- Blackhole routes intentionally set `blackhole = false` in the resource blocks even when the desired route is a blackhole route. This is not a logic error. The RouterOS provider documents `blackhole` as a presence flag rather than a meaningful boolean, and local/CI plans showed perpetual drift when the configuration used the intuitive `blackhole = true` form.
- Import pre-existing live BGP objects into this stack before the first apply that manages them so Terraform does not attempt to recreate active gateway routing state from scratch.

## Notes

- Routing in this repo is modeled only on the `GW` device unless a later change explicitly extends it elsewhere.
- Treat `routing.auto.tfvars` as committed source-of-truth configuration for non-secret live routing values.
- The current BGP scope in this stack is the live GW RouterOS BGP instance, templates, connections, and routing filter rules present at import time.
- The current blackhole workaround depends on provider behavior, not common Terraform boolean semantics:
- RouterOS marks the route as blackhole when the `blackhole` argument is present in the request, regardless of whether the provider sends `true` or `false`.
- The provider currently refreshes these routes back into Terraform state as `blackhole = false`.
- Setting `blackhole = true` therefore causes repeated `false -> true` drift even after a successful apply.
- Setting `blackhole = false` keeps the argument present in the request while matching the provider's readback value, which makes local plans and CI drift checks converge.
- Do not simplify this back to `blackhole = true` unless the upstream `terraform-routeros/routeros` provider changes its route resource semantics and local `terraform plan` confirms the workaround is no longer needed.
- Update this README when the routing data model, BGP scope, or nested stack layout changes.
