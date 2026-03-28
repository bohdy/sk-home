# Network Core

This stack manages the MikroTik router and switches that define the physical network core.
Gateway DHCP now lives in the nested
[`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md)
stack so DHCP can evolve with its own Terraform state and lifecycle.

## Managed Devices

- `GW`: `10.1.100.1`
- `Switch 1PP`: `10.1.100.2`
- `Switch 1NP`: `10.1.100.3`

## Terraform Connection Model

This parent root keeps the committed MikroTik device inventory and foundation
metadata for the physical network core.

The configured endpoint format for this repo remains `https://<host>` backed by
RouterOS `www-ssl`, but live DHCP provider configuration now lives in the nested
[`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md)
root. The parent root temporarily retains legacy RouterOS provider inputs so
Terraform can still read and remove DHCP objects from the old state during the
migration window.

## RouterOS Prerequisites

Before Terraform can manage these devices through the nested DHCP root or any
future RouterOS-backed resources:

1. Create or import a server certificate on each device.
2. Enable `www-ssl` on each device and assign that certificate.
3. Restrict `www-ssl` to your trusted admin subnet.
4. Create a dedicated automation user for Terraform.
5. Restrict management access to your trusted admin subnet.
6. Avoid using the main admin account for automation.

## Let's Encrypt Automation

The repository also includes GitHub Actions automation to issue and renew public
Let's Encrypt certificates for the RouterOS `www-ssl` service on these devices.

Key points for this setup:

- keep the public authoritative `bohdal.name` zone in Cloudflare so DNS-01 TXT
  records can be created automatically
- keep the host A records split-horizon or internal-only if you do not want the
  device management IPs published on the public internet
- run the workflow on the internal self-hosted runner so certificate deployment
  can reach `10.1.100.1`, `10.1.100.2`, and `10.1.100.3` over SSH
- provide an SSH-capable RouterOS automation account that can import
  certificates and update `/ip service www-ssl`

The committed inventory for certificate targets lives in
[`mikrotik-letsencrypt-targets.csv`](/Users/bohdy/git/sk-home/config/mikrotik-letsencrypt-targets.csv).
The automation workflow is
[`mikrotik-certificates.yml`](/Users/bohdy/git/sk-home/.github/workflows/mikrotik-certificates.yml),
and the deployment script is
[`mikrotik-renew-letsencrypt.sh`](/Users/bohdy/git/sk-home/scripts/mikrotik-renew-letsencrypt.sh).
The deployment script verifies that the uploaded PKCS#12 bundle and temporary
RouterOS import script are both visible in `/file` before it runs `/import`,
and RouterOS temp-file cleanup is best-effort after a successful import.

Required Bitwarden secrets:

- `CLOUDFLARE_API_TOKEN`: token allowed to edit DNS for the public zone
- `MIKROTIK_USERNAME`: RouterOS automation username reused for SSH uploads and CLI changes
- `MIKROTIK_SSH_PRIVATE_KEY`: private key for that automation account
- `MIKROTIK_SSH_KNOWN_HOSTS`: pinned host keys for the three MikroTik devices

The self-hosted GitHub runner and local operators should load these values
through [`load-bitwarden-secrets.sh`](/Users/bohdy/git/sk-home/scripts/load-bitwarden-secrets.sh)
with a `BWS_ACCESS_TOKEN` that stays outside the repository.

Suggested Cloudflare token scope:

- `Zone:DNS:Edit` for the `bohdal.name` zone only

Suggested RouterOS permissions:

- access to `ssh`
- access to `/certificate`
- access to `/ip service`

Manual `workflow_dispatch` runs can use the workflow's `acme_environment`
selector to target Let's Encrypt staging while validating the RouterOS upload
and import path. Manual runs can also use the `target_device` selector to
process either all inventory entries or one specific MikroTik hostname.
Scheduled runs and `main` branch runs remain on production and process the full
inventory.

## Local Configuration

The shared non-secret `network-core` configuration is committed in `network-core.auto.tfvars`.
Use `terraform.tfvars.example` only for local-only overrides or temporary inputs that should not become shared desired state.

Recommended sensitive input handling for nested MikroTik-backed roots such as
[`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md):

- keep `mikrotik_password` out of committed files
- use `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"` for local runs
  so `TF_VAR_mikrotik_password` and related values come from Bitwarden
- set `mikrotik_insecure = false` once certificate trust is configured
- on self-hosted GitHub runners, provide `bws` and `BWS_ACCESS_TOKEN` so
  workflows can load `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` from Bitwarden
- provide Cloudflare R2 credentials through `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION=auto`

The parent root keeps the same credential shape only as a temporary migration
bridge while old DHCP objects still exist in its remote state.

Example non-sensitive endpoint values:

- `mikrotik_gw_hosturl = "https://10.1.100.1"`
- `mikrotik_switch_1pp_hosturl = "https://10.1.100.2"`
- `mikrotik_switch_1np_hosturl = "https://10.1.100.3"`

## Notes

- DHCP in this repo is modeled only on the `GW` device and is managed in the nested
  [`dhcp`](/Users/bohdy/git/sk-home/terraform/stacks/network-core/dhcp/README.md)
  stack rather than in this parent root.
- Keep the legacy RouterOS provider wiring in this parent root until the old
  DHCP state has been migrated or cleaned up. Removing it too early breaks
  Terraform plan because the old state still references that provider.
- Treat `network-core.auto.tfvars` as committed source-of-truth configuration for non-secret live infrastructure values.
- Keep provider credentials shared only if the same automation account is intentionally used on all three devices.
- If credentials diverge later, split the username and password variables per device instead of hardcoding exceptions.
- Update this README when the RouterOS connection model or the split between parent and nested network-core roots changes.
