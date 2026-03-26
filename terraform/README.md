# Terraform

This directory contains the Terraform bootstrap for the `sk-home` infrastructure workspace.

## Purpose

The bootstrap is intentionally minimal. It provides:

- a stack-oriented Terraform layout with smaller failure domains
- a place for reusable modules shared across stacks
- documented input variables for environment-specific values
- example `.tfvars` files for local configuration without committing secrets

## Layout

- `modules/`: reusable Terraform modules shared across stacks
- `stacks/network-core/`: MikroTik router and switch foundations
- `stacks/wifi/`: UniFi wireless configuration
- `stacks/identity-edge/`: Cloudflare ZTNA and edge access controls
- `stacks/overlay/`: Tailscale tailnet and overlay-network settings

Each stack is its own Terraform root module with separate state, variables, and outputs.

## Getting Started

1. Install Terraform.
2. Choose the stack you want to work on under `stacks/`.
3. Copy that stack's `terraform.tfvars.example` to a local `.tfvars` file if you want local overrides.
4. Fill in environment-specific values without committing secrets.
5. Run `terraform init` inside the selected stack directory.
6. Run `terraform plan` inside the selected stack directory.

## Notes

- Keep secrets out of committed files.
- Prefer variables over hardcoded values when adding providers, modules, or resources.
- Keep physical networking, wireless, identity edge, and overlay networking in separate stacks unless there is a strong reason to couple them.
- The `network-core` stack is prepared for three MikroTik devices using aliased RouterOS providers, `apis://...:8729` endpoints, and variable-based credentials.
- GitHub Actions supports automatic and manual Terraform validation runs, expects `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` repository secrets for MikroTik-backed stacks, and tracks the latest verified Terraform and action versions.
- Update this README whenever the Terraform workflow or structure changes.
