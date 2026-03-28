# sk-home
Automation of home network / lab

## MikroTik Certificates

The repository includes GitHub Actions automation for issuing Let's Encrypt
certificates for MikroTik devices through the DNS-01 challenge against the
public `bohdal.name` Cloudflare zone.

The device hostnames can remain split-horizon or internal-only A records:

- `gw.bohdal.name` -> `10.1.100.1`
- `sw-1pp.bohdal.name` -> `10.1.100.2`
- `sw-1np.bohdal.name` -> `10.1.100.3`

That model works because Let's Encrypt only needs the temporary public
`_acme-challenge` TXT records for validation. The host A records themselves do
not need to exist publicly when DNS-01 is used.

The automation is defined in
[`mikrotik-certificates.yml`](.github/workflows/mikrotik-certificates.yml),
uses the committed inventory in
[`config/mikrotik-letsencrypt-targets.csv`](config/mikrotik-letsencrypt-targets.csv),
and installs certificates onto RouterOS over SSH from the internal self-hosted
runner. Before each RouterOS import, the deployment script verifies that the
uploaded PKCS#12 bundle and temporary import script are both visible on the
target device. Temporary RouterOS file cleanup is best-effort so a successful
certificate install does not fail only because a transient upload file is
already gone by the time cleanup runs.

Manual workflow runs can target Let's Encrypt staging for safe end-to-end
testing, and they can now scope deployment to `all` inventory entries or one
specific hostname. Scheduled runs and `main` branch runs stay on production and
process the full committed inventory.

## Terraform

The repository includes a Terraform bootstrap in [`terraform`](terraform).
Use the stack directories under [`terraform/stacks`](terraform/stacks) as separate Terraform root modules and keep the Terraform README updated as the workflow evolves.
GitHub Actions now validates only changed Terraform stacks automatically, and pushes to `main` apply changed stacks that are CI-ready for safe unattended deployment.
An hourly Terraform drift workflow also checks CI-ready stacks and publishes a drift plan artifact when live infrastructure diverges from the committed desired state.
