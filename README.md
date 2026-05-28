# sk-home

This repository was intentionally reset to an almost-empty learning repo.

The previous home-lab automation implementation was archived in Git before this reset:

- Archive branch: `archive-2026-04-23-pre-learning-reset`
- Archive tag: `archive-pre-learning-reset-2026-04-23`

Use those refs whenever you want to review or restore the original home-lab automation, scripts, workflows, and operational documentation.

## Current Goal

The active working tree is intentionally minimal. Keep only `README.md` and Codex-related files committed by default, then add new project files only when a specific learning task requires them.

The currently intended committed surface is:

- `README.md`
- `.gitignore`
- `AGENTS.md`
- repo-local Codex files under `.codex/`

## Rebuild Rules

- Reintroduce one concern at a time.
- Keep secrets outside the repo and load them through the shared secret-management approach when automation returns.
- Update documentation in the same task whenever behavior or layout changes.
- Keep production on `main` and publish new work through pull requests from descriptive branches.
- Do not keep placeholder project directories when they are not actively used.

## Active Terraform Stacks

The Talos Kubernetes learning cluster lives in `terraform/k3s/talos-cluster`. It creates a three-control-plane upstream Kubernetes cluster on Proxmox using Talos noCloud images, static VLAN 20 addressing, and Terraform-managed Talos bootstrap state.

The `main` Terraform workflow targets only the active rebuild path: `proxmox/images` and `k3s/talos-cluster`. The legacy Flatcar-backed `k3s/cluster` stack remains in the tree for reference, but it is intentionally excluded from the main workflow until the state lock and legacy path are retired.

## Local Development

The preferred local development environment is the repository devcontainer. It keeps Terraform, CI helper tools, and shell behavior closer to the environment used by automation, so use it for Terraform and workflow work unless a task specifically requires running on the host.

### Prerequisites

- Dev Containers support, such as VS Code Dev Containers or the `devcontainer` CLI
- [act](https://github.com/nektos/act) - Run GitHub Actions locally
- Docker - Required by act
- Bitwarden account with access to repository secrets

### Devcontainer

Open the repository in the devcontainer before running Terraform, `act`, or repository validation commands. Run the commands below from the repository root inside that container. From a host shell with the Dev Containers CLI installed, the container can be started with:

```bash
devcontainer up --workspace-folder .
```

### Environment Setup

1. Create a `.env` file in the repository root with your Bitwarden access token:
   ```bash
   BWS_ACCESS_TOKEN="your_bitwarden_access_token_here"
   ```

2. Get your Bitwarden access token from: Account Settings → Security → API Key

### Testing Workflows Locally

To test GitHub Actions workflows locally using act:

```bash
# Load environment variables and run Terraform workflow
source .env && act --workflows .github/workflows/terraform.yaml \
  -P self-hosted=node:18-bookworm \
  --container-architecture linux/amd64 \
  --secret BWS_ACCESS_TOKEN="$BWS_ACCESS_TOKEN"
```

**Important notes:**
- Uses `node:18-bookworm` Docker image (required for Bitwarden action compatibility)
- Secrets are retrieved from Bitwarden using the access token
- This ensures local testing matches CI/CD behavior exactly

### Running Terraform Locally

To run Terraform outside GitHub Actions, use the devcontainer or install Terraform, the Bitwarden Secrets Manager CLI (`bws`), and `jq` on the host. Load the same Bitwarden token from `.env` before fetching secrets. Use `set -a` while sourcing `.env` so child processes such as `bws` can read `BWS_ACCESS_TOKEN`:

```bash
set -a
source .env
set +a

export AWS_ACCESS_KEY_ID="$(bws secret get f1a17686-db90-4ae0-80aa-b43701584bab -o json | jq -r .value)"
export AWS_SECRET_ACCESS_KEY="$(bws secret get 31f0524c-b94e-4446-ba46-b43701586360 -o json | jq -r .value)"
```

`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are the Cloudflare R2 credentials used by Terraform's S3-compatible backend. If they are missing from the shell environment, `terraform init` and `terraform plan` will fail before evaluating stack resources with `No valid credential sources found`.

Choose the stack directory once, then reuse it for Terraform commands. `TF_STACK` must point at the directory below `terraform/`, without the leading `terraform/` prefix:

```bash
export TF_STACK="k3s/cluster"

terraform -chdir="terraform/${TF_STACK}" init
```

Terraform may create or update `.terraform.lock.hcl` for the selected stack during `init`; review and commit that lock file when the provider selection is intentional. Do not commit the generated `.terraform/` directory.

Load any stack-specific provider variables before planning. For MikroTik-backed stacks:

```bash
export TF_VAR_mikrotik_gw_hosturl="https://gw.bohdal.name/"
export TF_VAR_mikrotik_username="$(bws secret get 519790de-c23d-41f7-a838-b41b00c9444d -o json | jq -r .value)"
export TF_VAR_mikrotik_password="$(bws secret get 6b950dde-8f31-4d7b-9fdc-b41b00c993ca -o json | jq -r .value)"
```

For Proxmox-backed stacks:

```bash
export TF_VAR_proxmox_endpoint="$(bws secret get 704a25a3-5cb3-41a5-a0a1-b41c00c83189 -o json | jq -r .value)"
export TF_VAR_proxmox_api_token="$(bws secret get bec590dc-5777-441f-8f4b-b41c00c84280 -o json | jq -r .value)"
export TF_VAR_proxmox_ssh_username="$(bws secret get f6a9155e-b392-45b8-8254-b41c00c87486 -o json | jq -r .value)"
export TF_VAR_proxmox_ssh_private_key="$(bws secret get a64de379-c939-4d47-841e-b41c00c8641d -o json | jq -r .value)"
```

Run the plan for the selected stack:

```bash
terraform -chdir="terraform/${TF_STACK}" plan -out=tfplan
```

Keep shell tracing disabled while running these commands, and do not echo the exported values. A successful backend initialization only proves Terraform can access state; `plan` can still fail if the selected stack has missing or invalid resource arguments. Remove any generated `tfplan` file after inspection if you do not need to keep the binary plan file.

### Troubleshooting

- **OpenSSL errors**: Ensure you're using `node:18-bookworm` (not `node:18-bullseye`)
- **Access token errors**: Verify your Bitwarden access token is valid and has proper permissions
- **Docker issues**: Make sure Docker is running and you have sufficient permissions
