# Terraform

This directory contains the Terraform bootstrap for the `sk-home` infrastructure workspace.

## Purpose

The bootstrap is intentionally minimal. It provides:

- a stack-oriented Terraform layout with smaller failure domains
- a place for reusable modules shared across stacks
- documented input variables for environment-specific values
- example `.tfvars` files for local configuration without committing secrets
- a shared Bitwarden loader for CI and local credential injection

## Layout

- `modules/`: reusable Terraform modules shared across stacks
- `stacks/network-core/`: MikroTik router and switch foundations
- `stacks/network-core/interfaces/`: container directory for per-device MikroTik interface roots
- `stacks/network-core/interfaces/gw/`: MikroTik gateway bridge, VLAN, tunnel, and physical interface configuration
- `stacks/network-core/interfaces/switch-1pp/`: MikroTik Switch 1PP bridge, VLAN, and physical interface configuration
- `stacks/network-core/interfaces/switch-1np/`: MikroTik Switch 1NP bridge, VLAN, and physical interface configuration
- `stacks/network-core/dhcp/`: MikroTik gateway DHCP scopes, reservations, and DHCP options
- `stacks/network-core/routing/`: MikroTik gateway static routing and BGP configuration
- `stacks/wifi/`: UniFi wireless configuration
- `stacks/identity-edge/`: Cloudflare ZTNA and edge access controls
- `stacks/overlay/`: Tailscale tailnet and overlay-network settings

Each stack root is its own Terraform root module with separate state, variables, and outputs. Most stack roots live directly under `stacks/`, but nested roots are acceptable when a concern deserves separate state while still belonging to a broader domain such as `network-core`.

## Getting Started

1. Install Terraform.
2. Install `pre-commit` and `tflint` for local commit-time Terraform checks.
3. Run `pre-commit install` from the repository root once per clone.
4. Choose the stack you want to work on under `stacks/`.
5. Copy `.env.example` to `.env` and fill in local non-secret defaults.
6. Load the environment variables from `.env` into your shell.
7. Install the Bitwarden Secrets Manager CLI (`bws`) and set `BWS_ACCESS_TOKEN`.
8. Load Terraform credentials from Bitwarden with `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"`.
9. Copy that stack's `terraform.tfvars.example` to a local `.tfvars` file if you want local overrides.
10. Fill in environment-specific values without committing secrets.
11. Run `terraform init -reconfigure` inside the selected stack directory.
12. Run `terraform plan` inside the selected stack directory.

## Bitwarden Secrets

Bitwarden Secrets Manager is the source of truth for shared secret values in both GitHub Actions and local runs.

- Install `bws` on local machines and self-hosted GitHub runners.
- Set `BWS_ACCESS_TOKEN` outside the repository on any machine that needs to load secrets.
- Optionally set `BITWARDEN_PROJECT_ID` when the machine account can access more than one Bitwarden project and this repo should load only one scope.
- Use [`load-bitwarden-secrets.sh`](/Users/bohdy/git/sk-home/scripts/load-bitwarden-secrets.sh) to emit the exact environment variables expected by Terraform and the certificate automation.

Useful local commands:

- `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"`
- `eval "$(./scripts/load-bitwarden-secrets.sh mikrotik-certificates)"`

## Local Pre-Commit Checks

The repository commits its pre-commit policy so every clone can run the same fast local checks before code reaches CI.

- Markdown docs are normalized so prose and list items stay on one physical line per block.
- `terraform fmt` runs across tracked Terraform files to keep formatting stable.
- `tflint` runs only against the Terraform stack roots affected by the current change set so commit-time linting stays fast.
- Changes under `terraform/modules`, [`.tflint.hcl`](/Users/bohdy/git/sk-home/.tflint.hcl), or [`.pre-commit-config.yaml`](/Users/bohdy/git/sk-home/.pre-commit-config.yaml) fan linting out to every stack because shared Terraform behavior may change.

Useful local commands:

- `pre-commit run --all-files`
- `./scripts/run-tflint-stacks.sh`

Keep `terraform validate` and provider/backend-sensitive checks in GitHub Actions. Local pre-commit hooks intentionally stop at formatting and linting so commits do not depend on remote backend access, provider downloads, or live infrastructure credentials.

## Notes

- Keep secrets out of committed files.
- Keep `BWS_ACCESS_TOKEN` outside the repository and load live credentials from Bitwarden instead of duplicating them in `.env`.
- Prefer variables over hardcoded values when adding providers, modules, or resources.
- Keep physical networking, DHCP, wireless, identity edge, and overlay networking in separate stacks unless there is a strong reason to couple them.
- The `network-core` stack is prepared for three MikroTik devices using aliased RouterOS providers, `https://...` endpoints backed by `www-ssl`, and variable-based credentials.
- The nested `network-core/interfaces` directory now contains per-device roots for the gateway and both switches so interface lifecycle changes can evolve independently with smaller failure domains.
- The nested `network-core/dhcp` stack manages only gateway DHCP resources so that scopes, reservations, and DHCP options can change independently from the rest of `network-core`.
- The nested `network-core/routing` stack manages only gateway routing resources so that static routes and BGP configuration can change independently from the rest of `network-core`.
- The `network-core/routing` stack uses a documented provider workaround for RouterOS blackhole routes: the route resources keep the `blackhole` argument present but set it to `false` so Terraform plans stay convergent with the current `terraform-routeros/routeros` refresh behavior. See the routing stack README before changing that logic.
- GitHub Actions detects changed Terraform stacks automatically, validates only the affected stacks on pull requests and branch pushes, and lets manual runs target one stack or all stacks.
- Pushes to `main` run `terraform apply` only for changed stacks that have committed non-secret CI inputs and are explicitly marked CI-ready in the workflow. Today that includes `network-core`, `network-core/interfaces/gw`, `network-core/interfaces/switch-1pp`, `network-core/interfaces/switch-1np`, `network-core/dhcp`, and `network-core/routing`.
- Manual workflow runs expose `action` and `stack` inputs so operators can choose validate-only runs or apply CI-ready stacks explicitly.
- A separate hourly `terraform-drift` workflow checks CI-ready stacks for drift with `terraform plan -detailed-exitcode`, keeps the Terraform CLI wrapper disabled so exit code `2` remains visible to the shell, uploads the plain-text plan when drift is found, and fails the run so the drift is visible in Actions.
- When splitting existing resources into a new stack root, migrate or import the existing state before the first apply so the old root does not try to delete objects that moved into the new root.
- Self-hosted GitHub runners must provide `bws` and `BWS_ACCESS_TOKEN` so the workflows can load Bitwarden secrets at runtime.
- All stacks commit the stable Cloudflare R2 backend settings directly in `backend.tf` and keep only credentials external.
- Bitwarden should store `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `MIKROTIK_USERNAME`, `MIKROTIK_PASSWORD`, `CLOUDFLARE_API_TOKEN`, `MIKROTIK_SSH_PRIVATE_KEY`, and `MIKROTIK_SSH_KNOWN_HOSTS` for this repo.
- Update this README whenever the Terraform workflow or structure changes.
