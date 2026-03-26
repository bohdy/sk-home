# Network Core

This stack manages the MikroTik router and switches that define the physical network core.

## Managed Devices

- `GW`: `10.1.100.1`
- `Switch 1PP`: `10.1.100.2`
- `Switch 1NP`: `10.1.100.3`

## Terraform Connection Model

This stack uses the official `terraform-routeros/routeros` provider with three aliased provider configurations:

- `routeros.gw`
- `routeros.switch_1pp`
- `routeros.switch_1np`

Each alias points to a separate MikroTik device so future resources can target the correct router or switch explicitly.
The configured endpoint format for this repo is `apis://<host>:8729`.

## RouterOS Prerequisites

Before Terraform can manage these devices:

1. Enable `api-ssl` on each device.
2. Restrict `api-ssl` to your trusted admin subnet.
3. Create a dedicated automation user for Terraform.
4. Restrict management access to your trusted admin subnet.
5. Avoid using the main admin account for automation.

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

Required GitHub repository secrets:

- `CLOUDFLARE_API_TOKEN`: token allowed to edit DNS for the public zone
- `MIKROTIK_SSH_USERNAME`: RouterOS automation username for SSH uploads and CLI changes
- `MIKROTIK_SSH_PRIVATE_KEY`: private key for that automation account
- `MIKROTIK_SSH_KNOWN_HOSTS`: pinned host keys for the three MikroTik devices

Suggested Cloudflare token scope:

- `Zone:DNS:Edit` for the `bohdal.name` zone only

Suggested RouterOS permissions:

- access to `ssh`
- access to `/certificate`
- access to `/ip service`

## Local Configuration

Copy `terraform.tfvars.example` to a local `.tfvars` file or use `TF_VAR_...` environment variables for sensitive values.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `TF_VAR_mikrotik_password` for local runs when practical
- set `mikrotik_insecure = false` once certificate trust is configured
- in GitHub Actions, provide `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` repository secrets
- provide Cloudflare R2 credentials through `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION=auto`

Example non-sensitive endpoint values:

- `mikrotik_gw_hosturl = "apis://10.1.100.1:8729"`
- `mikrotik_switch_1pp_hosturl = "apis://10.1.100.2:8729"`
- `mikrotik_switch_1np_hosturl = "apis://10.1.100.3:8729"`

## Notes

- DHCP in this repo is modeled only on the `GW` device unless a later change explicitly extends it elsewhere.
- Define DHCP scopes through the `dhcp_scopes` variable so pools, server bindings, and per-network options stay synchronized.
- Keep provider credentials shared only if the same automation account is intentionally used on all three devices.
- If credentials diverge later, split the username and password variables per device instead of hardcoding exceptions.
- Update this README when the RouterOS connection model or managed inventory changes.
