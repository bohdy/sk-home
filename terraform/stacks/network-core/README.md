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

## Local Configuration

Copy `terraform.tfvars.example` to a local `.tfvars` file or use `TF_VAR_...` environment variables for sensitive values.
Copy `backend.r2.hcl.example` to `backend.r2.hcl` and fill in your R2 bucket and Cloudflare account ID before running `terraform init -reconfigure -backend-config=backend.r2.hcl`.

Recommended sensitive input handling:

- keep `mikrotik_password` out of committed files
- use `TF_VAR_mikrotik_password` for local runs when practical
- set `mikrotik_insecure = false` once certificate trust is configured
- in GitHub Actions, provide `MIKROTIK_USERNAME` and `MIKROTIK_PASSWORD` repository secrets
- provide Cloudflare R2 credentials through `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION=auto` instead of hardcoding them in backend files

Example non-sensitive endpoint values:

- `mikrotik_gw_hosturl = "apis://10.1.100.1:8729"`
- `mikrotik_switch_1pp_hosturl = "apis://10.1.100.2:8729"`
- `mikrotik_switch_1np_hosturl = "apis://10.1.100.3:8729"`

## Notes

- Keep provider credentials shared only if the same automation account is intentionally used on all three devices.
- If credentials diverge later, split the username and password variables per device instead of hardcoding exceptions.
- Update this README when the RouterOS connection model or managed inventory changes.
