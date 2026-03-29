# WiFi Stack

This stack is a documented Terraform destination for future UniFi wireless configuration, but it is intentionally providerless today.

## Current State

The tracked files in this root establish shared stack context, remote-state placement, and operator-facing inputs without yet managing live UniFi resources.

That means:

- `terraform validate` should stay green
- no `required_providers` block is present yet because the root does not declare any provider-backed resources
- the main Terraform workflow keeps this stack validate-only and does not generate plans or applies for it

## Why It Exists

The repository layout reserves separate Terraform roots for concerns that deserve their own state and review surface.

Wireless configuration belongs in its own root rather than being folded into application, identity, or cluster stacks, even before the first managed UniFi resources are added.

## Local Use

Use [`terraform.tfvars.example`](/Users/bohdy/git/sk-home/terraform/stacks/wifi/terraform.tfvars.example) only for local-only overrides or exploratory inputs that should not become committed shared state.

Treat this root as bootstrap structure until real wireless resources are introduced and documented here.
