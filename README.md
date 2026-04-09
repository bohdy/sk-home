# sk-home
Automation of home network / lab

## MikroTik Certificates

The repository includes GitHub Actions automation for issuing Let's Encrypt certificates for MikroTik devices through the DNS-01 challenge against the public `bohdal.name` Cloudflare zone.

The device hostnames can remain split-horizon or internal-only A records:

- `gw.bohdal.name` -> `10.1.100.1`
- `sw-1pp.bohdal.name` -> `10.1.100.2`
- `sw-1np.bohdal.name` -> `10.1.100.3`

That model works because Let's Encrypt only needs the temporary public `_acme-challenge` TXT records for validation. The host A records themselves do not need to exist publicly when DNS-01 is used.

The automation is defined in [`mikrotik-certificates.yml`](.github/workflows/mikrotik-certificates.yml), uses the committed inventory in [`config/mikrotik-letsencrypt-targets.csv`](config/mikrotik-letsencrypt-targets.csv), and installs certificates onto RouterOS over SSH from the internal self-hosted runner. The runner now loads Cloudflare, MikroTik, and Telegram configuration from Bitwarden Secrets Manager through the shared [`load-bitwarden-secrets.sh`](scripts/load-bitwarden-secrets.sh) helper instead of GitHub repository secrets. Before each RouterOS import, the deployment script verifies that the uploaded PKCS#12 bundle and temporary import script are both visible on the target device. Temporary RouterOS file cleanup is best-effort so a successful certificate install does not fail only because a transient upload file is already gone by the time cleanup runs. Before renewing, the script checks the certificate currently served by each device on `www-ssl` and only renews when that live certificate will expire within 4 days by default. You can override that threshold with `MIKROTIK_CERTIFICATE_RENEWAL_WINDOW_DAYS` when a different renewal window is needed.

Manual workflow runs can target Let's Encrypt staging for safe end-to-end testing, and they can now scope deployment to `all` inventory entries or one specific hostname. Scheduled runs and `main` branch runs stay on production and process the full committed inventory. The workflow now sends Telegram notifications when a certificate is actually renewed and deployed, and when the renewal job fails after Telegram settings have been loaded. Healthy no-op renewal checks stay quiet.

## Terraform

The repository includes a Terraform bootstrap in [`terraform`](terraform). Use the stack directories under [`terraform/stacks`](terraform/stacks) as separate Terraform root modules and keep the Terraform README updated as the workflow evolves. Local commit-time Terraform checks are managed through a committed [`pre-commit`](https://pre-commit.com/) configuration that runs `terraform fmt` and `tflint` before changes are committed. Install `pre-commit` and `tflint` locally, run `pre-commit install` once per clone, and use `pre-commit run --all-files` after changing Terraform tooling or lint rules. The same pre-commit configuration also normalizes Markdown so repo docs keep one physical line per paragraph or list item. Local Terraform and certificate runs now share Bitwarden Secrets Manager as the recommended secret source through [`load-bitwarden-secrets.sh`](scripts/load-bitwarden-secrets.sh), and CI can now materialize kubeconfig files from either the default cluster secret names (`KUBECONFIG_CONTENT`, `HOME_KUBECONFIG_CONTENT`, `KUBECONFIG_CONTENT_HOME`) or the k3s-specific names (`K3S_KUBECONFIG_CONTENT`, `KUBECONFIG_CONTENT_K3S`) per stack. GitHub Actions now validates only changed Terraform stacks automatically, and pull request-time plan artifacts for the imported edge, overlay, cluster, Blocky, UniFi, observability, and Proxmox stacks now run as well. Those imported-stack plans remain read-only: pushes to `main` still apply only the explicitly CI-ready stacks, while the migrated stacks hydrate a few preserved secret values from live Kubernetes secrets during validation so Terraform can plan without reintroducing Pulumi-era secrets into the repo. A separate repo-hygiene workflow now checks tracked Markdown normalization, shell-script syntax, and GitHub Actions workflow syntax so repo-wide maintenance changes fail fast before merge. A twice-daily Terraform drift workflow checks the current drift-enabled stacks and publishes a drift plan artifact when live infrastructure diverges from the committed desired state. The scheduled drift checks run at `06:17` and `18:17` UTC year-round, so Prague-local execution shifts by one hour when daylight saving time changes. The Terraform workflows now use bounded concurrency, explicit job and step timeouts, and a shared Terraform plugin cache on the self-hosted runner so stale or slow runs do not occupy the runner indefinitely. The drift workflow now sends Telegram notifications when drift is detected for a stack and when the job fails for a non-drift reason after Telegram settings have been loaded. The repo now also contains explicit Terraform migration destinations for the legacy Pulumi edge, overlay, cluster, Blocky, UniFi, observability, and Proxmox domains so imports can happen inside one consistent state layout.

## Telegram Notifications

Telegram delivery uses the direct Bot API through the shared [`send-telegram-message.sh`](scripts/send-telegram-message.sh) helper so the workflows do not depend on an extra third-party action.

For first-time setup:

1. Create a bot with BotFather and copy the bot token.
2. Add the bot to the destination chat.
3. Send at least one message in that chat so the bot can address it.
4. Discover the chat ID with the Bot API `getUpdates` method or another trusted Telegram chat ID lookup flow.
5. Store `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in Bitwarden Secrets Manager for this repository.
6. Optionally store `TELEGRAM_MESSAGE_THREAD_ID` when the destination is a Telegram forum topic and the notifications should be routed into one specific thread.

Notifications are intentionally concise. They include device or stack names, the high-level outcome, and a GitHub Actions run link, but they do not send certificate bodies, Terraform plan contents, or other secret-adjacent operational output to Telegram.
