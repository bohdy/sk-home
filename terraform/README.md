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
3. Copy `.env.example` to `.env` and fill in local credentials and defaults.
4. Load the environment variables from `.env` into your shell.
5. Copy that stack's `terraform.tfvars.example` to a local `.tfvars` file if you want local overrides.
6. Fill in environment-specific values without committing secrets.
7. Run `terraform init -reconfigure` inside the selected stack directory.
8. Run `terraform plan` inside the selected stack directory.

## Notes

- Keep secrets out of committed files.
- Store local credentials in `.env`, not in committed Terraform files.
- Prefer variables over hardcoded values when adding providers, modules, or resources.
- Keep physical networking, wireless, identity edge, and overlay networking in separate stacks unless there is a strong reason to couple them.
- The `network-core` stack is prepared for three MikroTik devices using aliased RouterOS providers, `https://...` endpoints backed by `www-ssl`, and variable-based credentials.
- GitHub Actions detects changed Terraform stacks automatically, validates only the affected stacks on pull requests and branch pushes, and lets manual runs target one stack or all stacks.
- Pushes to `main` run `terraform apply` only for changed stacks that have committed non-secret CI inputs. Today that means `network-core`; the other stacks remain validate-only until they gain committed CI-ready inputs.
- Manual workflow runs expose `action` and `stack` inputs so operators can choose validate-only runs or apply CI-ready stacks explicitly.
- A separate hourly `terraform-drift` workflow checks CI-ready stacks for drift with `terraform plan -detailed-exitcode`, uploads the plain-text plan when drift is found, and fails the run so the drift is visible in Actions.
- GitHub Actions expects `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` repository secrets for MikroTik-backed stacks and tracks the latest verified Terraform and action versions.
- All stacks commit the stable Cloudflare R2 backend settings directly in `backend.tf` and keep only credentials external.
- GitHub Actions remote-state initialization expects repository secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
- Update this README whenever the Terraform workflow or structure changes.
