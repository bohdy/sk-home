# Network Core Interfaces

This directory groups the per-device Terraform roots that manage MikroTik
interface topology and interface metadata without expanding the parent
`network-core` Terraform root into a catch-all stack.

## Per-Device Roots

- [`gw`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/interfaces/gw/README.md):
  gateway bridge, VLAN, tunnel, and physical interface state
- [`switch-1pp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/interfaces/switch-1pp/README.md):
  Switch 1PP bridge, VLAN, and physical interface state
- [`switch-1np`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/interfaces/switch-1np/README.md):
  Switch 1NP bridge, VLAN, and physical interface state

## Purpose

The interface domain is now split per device because that matches the real
operational blast radius better than one shared state:

- one broken import or provider issue affects only one device
- state locking stays per device during iterative network work
- bridge, VLAN, and tunnel changes can be imported and reviewed independently
- the gateway's higher-risk topology changes no longer share state with switch
  maintenance

The parent
[`network-core`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/README.md)
stack remains focused on committed device inventory and shared MikroTik
connection metadata. The nested
[`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md)
and
[`routing`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/routing/README.md)
roots remain the dedicated homes for gateway DHCP and routing concerns.

## Shared Implementation

The three per-device roots reuse the shared module in
[`terraform/modules/routeros-device-interfaces`](/Users/bohdy/git/sk-home/terraform/modules/routeros-device-interfaces)
so the gateway and switch stacks share one RouterOS resource implementation
path without sharing one Terraform state file.

## Local Configuration

Each per-device root commits its own non-secret `interfaces.auto.tfvars` file.
Use the root-specific `terraform.tfvars.example` files only for local-only
overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` from the repo
  root for local runs so `TF_VAR_mikrotik_password` and related values come
  from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured
- on self-hosted GitHub runners, provide `bws` and `BWS_ACCESS_TOKEN` so
  workflows can load `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` from Bitwarden

## Rollout Notes

- The current `gw`, `switch-1pp`, and `switch-1np` roots were imported from
  the live devices before review so Terraform state already matches the
  existing bridge, bridge port, bridge VLAN, VLAN interface, tunnel, and
  physical interface objects tracked by this repo.
- If future work adds pre-existing live RouterOS objects that are not yet in
  state, import them into the matching per-device root before the first apply
  that manages them.
- The per-device split is intentionally more import-friendly than the old
  shared interfaces root because each state now mirrors one actual device.
- Treat each root's `interfaces.auto.tfvars` file as committed source-of-truth
  configuration for non-secret live interface values.
