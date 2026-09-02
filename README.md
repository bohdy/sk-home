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

## Active OpenTofu Stacks

The Talos Kubernetes learning cluster lives in `terraform/k3s/talos-cluster`. It creates a three-control-plane, three-worker upstream Kubernetes cluster on Proxmox using Talos noCloud images, static VLAN 20 addressing, and OpenTofu-managed Talos bootstrap state.

Kubernetes add-ons live in `kubernetes/`. Cilium is bootstrapped first as the cluster CNI and BGP speaker, then Flux reconciles the committed Cilium LoadBalancer IPAM and BGP custom resources from Git.

The trusted `main` OpenTofu workflow plans all active stacks: `network/gw/interfaces`, `network/gw/dhcp`, `k3s/talos-cluster`, and `cloudflare/tunnel`. It applies only `k3s/talos-cluster` on `main`; gateway and Cloudflare changes stay plan-only because they have higher operational blast radius. The gateway firewall has its own targeted, production-gated apply path because the RouterOS provider can fail unrelated gateway resources during a full plan.

The repository keeps the historical `terraform/` directory name and existing `terraform.tfstate` object keys during the first OpenTofu migration. After the first successful OpenTofu apply, treat the retained remote state objects as OpenTofu-owned.

## Local Development

The repository devcontainer is the required local development environment. It keeps OpenTofu, CI helper tools, and shell behavior aligned with automation, so run local development, OpenTofu, workflow, and validation commands inside it. Use the host only to start or enter the devcontainer.

### Prerequisites

- Dev Containers support, such as VS Code Dev Containers or the `devcontainer` CLI
- Docker - Runs the devcontainer and its Docker-outside-of-Docker feature
- Bitwarden account with access to repository secrets

### Devcontainer

Open the repository in the devcontainer before running OpenTofu, `act`, or repository validation commands. Run the commands below from the repository root inside that container. From a host shell with the Dev Containers CLI installed, the container can be started with:

```bash
devcontainer up --workspace-folder .
```

The devcontainer post-create step trusts the repository `mise.toml`, installs the configured tools, installs the Git pre-commit hook through `mise exec`, and enables mise for later interactive bash sessions. The devcontainer image also provides repository tools such as `git`, `act`, `bws`, and `jq`. Do not install repository or workflow tools on the host; add missing tools to `.devcontainer/Dockerfile`, `.devcontainer/devcontainer.json`, or `mise.toml` instead.

### Environment Setup

1. Create a `.env` file in the repository root with your Bitwarden access token:
   ```bash
   BWS_ACCESS_TOKEN=your_bitwarden_access_token_here
   ```

   The devcontainer loads this ignored file as Docker's environment file, so use the unquoted `KEY=value` format. Its post-create bootstrap removes one complete matching pair of surrounding single or double quotes from `BWS_ACCESS_TOKEN` before `bws` uses it, including in later Bash sessions, and rejects an unmatched quote. The bootstrap keeps BWS state disabled through a local `[profiles.default]` configuration with `state_opt_out = "true"`; do not add `.env` to Git or copy its values into `devcontainer.json`.

2. Get your Bitwarden access token from: Account Settings → Security → API Key

### Testing Workflows Locally

Run the credential-free pull-request validation workflow locally without loading `.env` or passing any secret:

```bash
act --workflows .github/workflows/terraform-pr-validation.yaml \
  -P ubuntu-latest=node:24-bookworm \
  --container-architecture linux/amd64
```

Run the trusted workflow locally only when testing Bitwarden-backed planning behavior:

```bash
# Load environment variables and run the trusted OpenTofu workflow
source .env && act --workflows .github/workflows/terraform.yaml \
  -P self-hosted=node:18-bookworm \
  -P ubuntu-latest=node:24-bookworm \
  --container-architecture linux/amd64 \
  --secret BWS_ACCESS_TOKEN="$BWS_ACCESS_TOKEN"
```

**Important notes:**
- The pull-request workflow intentionally has no Bitwarden token, remote backend credentials, provider credentials, plan creation, or artifact upload.
- The trusted workflow uses the `node:18-bookworm` Docker image for Bitwarden action compatibility and must be run only against trusted repository contents.
- Local `act` runs do not reproduce GitHub production-environment approvals or self-hosted runner behavior exactly.

### GitHub Actions Trust Boundaries

`.github/workflows/terraform-pr-validation.yaml` is the only OpenTofu workflow triggered by pull requests. It uses an ephemeral hosted runner, initializes every stack with `-backend=false`, validates configuration without contacting infrastructure, and never retrieves secrets or creates binary plans.

`.github/workflows/terraform.yaml` is trusted-only. It runs for pushes to `main` and manual dispatches from `main`, retrieves Bitwarden values only for those trusted events, and creates immutable plan artifacts only during trusted runs for the existing production-gated apply jobs. A manual dispatch pointed at any other ref fails before credential retrieval, and multiple mutation inputs fail closed.

### Running OpenTofu Locally

To run OpenTofu outside GitHub Actions, use the repository devcontainer. Do not install or run OpenTofu, the Bitwarden Secrets Manager CLI (`bws`), or `jq` directly on the host. Load the same Bitwarden token from `.env` before fetching secrets. Use `set -a` while sourcing `.env` so child processes such as `bws` can read `BWS_ACCESS_TOKEN`:

```bash
set -a
source .env
set +a

export AWS_ACCESS_KEY_ID="$(bws secret get f1a17686-db90-4ae0-80aa-b43701584bab -o json | jq -r .value)"
export AWS_SECRET_ACCESS_KEY="$(bws secret get 31f0524c-b94e-4446-ba46-b43701586360 -o json | jq -r .value)"
```

`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are the Cloudflare R2 credentials used by OpenTofu's S3-compatible backend. If they are missing from the shell environment, `tofu init` and `tofu plan` will fail before evaluating stack resources with `No valid credential sources found`.

The reusable Cloudflare Tunnel control-plane stack lives in `terraform/cloudflare/tunnel`. It remains plan-only on ordinary pushes and owns Grafana's and UniFi's public DNS, HTTPS tunnel routes, exact Google identity policies, and the terminal `404` fallback. Both applications rely on the owner's Google account for strong authentication instead of adding an independent Cloudflare MFA prompt.

The Talos stack applies automatically only after a push to `main`. Gateway and Cloudflare stacks remain plan-only by default. To apply a reviewed gateway change through the trusted GitHub Actions Bitwarden integration, manually dispatch the workflow from `main` with the explicit gateway flag:

```bash
gh workflow run terraform.yaml --ref main -f apply_gateway=true -f apply_gateway_snmp=false -f plan_gateway_snmp=false -f apply_gateway_dhcp=false -f apply_gateway_ipfix=false -f apply_cloudflare=false
```

The gated gateway job uses the immutable gateway plan artifact produced earlier in the same trusted run, requests only the gateway's Bitwarden values, and runs in the `production` GitHub environment. OpenTofu workflow runs are serialized and an active run is never cancelled by a newer invocation. A gateway dispatch does not apply the Talos or Cloudflare stacks.

Capture the read-only RouterOS firewall baseline before enabling or reviewing the firewall policy:

```bash
gh workflow run routeros-firewall-inventory.yaml --ref main
```

The inventory workflow runs only from `main`, uses Bitwarden-backed RouterOS credentials, projects only non-secret metadata, and uploads no private keys, preshared keys, passwords, or raw API responses. Review its artifact before changing the gateway firewall policy or dispatching the targeted firewall apply.

Apply the reviewed firewall policy through its dedicated immutable artifact path:

```bash
gh workflow run terraform.yaml --ref main \
  -f apply_gateway=false \
  -f apply_gateway_snmp=false \
  -f plan_gateway_snmp=false \
  -f apply_gateway_firewall=true \
  -f apply_gateway_dhcp=false \
  -f apply_gateway_ipfix=false \
  -f apply_cloudflare=false
```

The first targeted firewall artifact adopted only verified existing rules and failed closed if it contained a delete or replacement. Its temporary import blocks were removed after the adoption apply and a clean follow-up plan is required. Broad default-deny policy and declarative WireGuard peers remain separate follow-up stages.

Adopt the verified gateway WireGuard interfaces and peers through the separate targeted path after the focused firewall contract is present:

```bash
gh workflow run terraform.yaml --ref main \
  -f apply_gateway=false \
  -f apply_gateway_snmp=false \
  -f plan_gateway_snmp=false \
  -f apply_gateway_firewall=false \
  -f apply_gateway_wireguard=true \
  -f apply_gateway_dhcp=false \
  -f apply_gateway_ipfix=false \
  -f apply_cloudflare=false
```

The WireGuard path imported only public peer configuration and interface identity; private and preshared keys remain sensitive state and are ignored during adoption. Its temporary import blocks were removed after the production-gated apply, and a clean follow-up plan is required.

Terraform/OpenTofu is the preferred ownership path for infrastructure and managed-device configuration. Direct API or CLI changes are reserved for documented break-glass work and must be adopted into state immediately. To import or update only the gateway SNMP communities while the pinned RouterOS provider cannot safely apply unrelated IP-address and BGP resources, dispatch the targeted workflow from `main`:

```bash
gh workflow run terraform.yaml --ref main -f apply_gateway=false -f apply_gateway_snmp=true -f plan_gateway_snmp=false -f apply_gateway_dhcp=false -f apply_gateway_ipfix=false -f apply_cloudflare=false
```

The targeted job creates an immutable plan containing only `routeros_snmp_community.observability_v2` and `routeros_snmp_community.observability_v3`, then applies that artifact in the `production` environment.

Apply the reviewed DHCP plan, including DNS servers advertised to LAN clients, through its separate targeted path:

```bash
gh workflow run terraform.yaml --ref main -f apply_gateway=false -f apply_gateway_snmp=false -f plan_gateway_snmp=false -f apply_gateway_dhcp=true -f apply_gateway_ipfix=false -f apply_cloudflare=false
```

That job applies the immutable full DHCP-stack plan in the `production` environment without evaluating the provider-blocked gateway interface and BGP resources. DHCP leases must already be static before they are added as `routeros_ip_dhcp_server_lease` resources; the repository does not use imperative dynamic-to-static conversion helpers.

Publish or update Grafana's or UniFi's Cloudflare tunnel, DNS, and Access configuration only through the reviewed Cloudflare plan path:

```sh
gh workflow run terraform.yaml --ref main -f apply_gateway=false -f apply_gateway_snmp=false -f plan_gateway_snmp=false -f apply_gateway_dhcp=false -f apply_gateway_ipfix=false -f apply_cloudflare=true
```

The six manual mutation inputs and the dedicated SNMP plan-only input are mutually exclusive; selecting more than one fails before credential retrieval. The Cloudflare job consumes the matrix plan artifact created in the same trusted run and requires the `production` environment before changing public routing or Access.

The dedicated MikroTik certificate workflow is a production-gated renewal path that runs separately from the general OpenTofu workflow. It uses Cloudflare DNS-01 and retains the ACME account and certificate key only in encrypted R2 state; its plan is deliberately not uploaded as an artifact. The first recovery of the currently expired or unreachable gateway certificate requires the narrowly scoped bootstrap option; that one-time path uses the gateway's private HTTP REST endpoint, forces the stack-owned leaf import to displace ambiguous legacy certificate names, renames the imported leaf by its public fingerprint, and verifies the bound leaf. The installer writes each temporary file through the RouterOS REST execute endpoint because this device rejects file contents in the REST file-create body; it uploads only the leaf's immediate issuer because RouterOS also rejects the full multi-certificate issuer bundle, while client trust stores provide the remaining root chain. Normal and scheduled runs use HTTPS by DNS name. Every weekly run imports a changed ACME leaf when needed and reconciles the addressed RouterOS `www-ssl` listener to the newest unexpired private-key certificate, after which the workflow verifies the RouterOS TLS connection:

```sh
gh workflow run mikrotik-certificates.yaml --ref main \
  -f bootstrap_gateway_certificate=true
```

Follow the verification commands in `terraform/network/gw/certificates/README.md` immediately after the initial apply. The workflow then checks weekly and renews automatically within the 30-day ACME threshold; the `production` environment remains the final approval boundary.

If the certificate plan reports that more than one `www-ssl` service exists, dispatch `routeros-service-inventory.yaml` from `main` to collect read-only diagnostic metadata. Do not delete services by their IDs: this gateway returns unstable duplicate IDs. The certificate stack instead discovers the one addressed listener and invokes RouterOS's documented `ip service set` action during every certificate workflow, so the built-in service is reconciled without provider adoption by an ambiguous name.

Choose the stack directory once, then reuse it for OpenTofu commands. `TF_STACK` must point at the directory below `terraform/`, without the leading `terraform/` prefix:

```bash
export TF_STACK="k3s/talos-cluster"

tofu -chdir="terraform/${TF_STACK}" init
```

OpenTofu may create or update `.terraform.lock.hcl` for the selected stack during `init`; review and commit that lock file when the provider selection is intentional. Do not commit the generated `.terraform/` directory.

Load any stack-specific provider variables before planning. For MikroTik-backed stacks:

```bash
export TF_VAR_mikrotik_gw_hosturl="https://gw.bohdal.name/"
export TF_VAR_mikrotik_username="$(bws secret get 519790de-c23d-41f7-a838-b41b00c9444d -o json | jq -r .value)"
export TF_VAR_mikrotik_password="$(bws secret get 6b950dde-8f31-4d7b-9fdc-b41b00c993ca -o json | jq -r .value)"
export TF_VAR_kubernetes_bgp_tcp_md5_key="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
```

`TF_VAR_kubernetes_bgp_tcp_md5_key` is the shared TCP MD5 key used by Cilium and the MikroTik gateway for Kubernetes BGP sessions. Create the Bitwarden item before planning the gateway stack and keep the secret ID out of command history when possible.

For Proxmox-backed stacks:

```bash
export TF_VAR_proxmox_endpoint="$(bws secret get 704a25a3-5cb3-41a5-a0a1-b41c00c83189 -o json | jq -r .value)"
export TF_VAR_proxmox_api_token="$(bws secret get bec590dc-5777-441f-8f4b-b41c00c84280 -o json | jq -r .value)"
export TF_VAR_proxmox_ssh_username="$(bws secret get f6a9155e-b392-45b8-8254-b41c00c87486 -o json | jq -r .value)"
export TF_VAR_proxmox_ssh_private_key="$(bws secret get a64de379-c939-4d47-841e-b41c00c8641d -o json | jq -r .value)"
```

The Talos stack also manages the shared read-only Proxmox exporter identity and matching root `PVEAuditor` ACLs for its dedicated group and privilege-separated token. Its passwordless user belongs only to that group, so the token remains limited by the intersection of both read-only permission sets. The generated full API token is a sensitive OpenTofu output handed once to dedicated Bitwarden item `SK-TALOS-PROXMOX-EXPORTER-API-TOKEN` by an authorized operator. The read-only CI identity injects that item after every apply, and the workflow fails unless the masked Bitwarden and state values match exactly.

Run the plan for the selected stack:

```bash
tofu -chdir="terraform/${TF_STACK}" plan -out=tofuplan
```

Keep shell tracing disabled while running these commands, and do not echo the exported values. A successful backend initialization only proves OpenTofu can access state; `plan` can still fail if the selected stack has missing or invalid resource arguments. Remove any generated `tofuplan` file after inspection if you do not need to keep the binary plan file.

### Troubleshooting

- **OpenSSL errors**: Ensure you're using `node:18-bookworm` (not `node:18-bullseye`)
- **Access token errors**: Verify your Bitwarden access token is valid and has proper permissions
- **Docker issues**: Make sure Docker is running and you have sufficient permissions
