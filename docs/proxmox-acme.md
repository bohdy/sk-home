# Proxmox management TLS

The Proxmox node keeps its installed short node name `pve`. Proxmox VE requires a node's hostname and IP configuration to be final before it joins a cluster, so this repository does not rename an installed node to change its management FQDN.

`pve.bohdal.name` is the canonical management endpoint and `pve.sk.bohdal.name` remains a compatibility alias. Internal split DNS maps both names to `10.1.100.201`; Proxmox must serve one publicly trusted certificate with both names as DNS subject alternative names. The Kubernetes Proxmox exporter uses the canonical name and normal system trust, so its TLS verification remains enabled without committing a private CA.

## ACME ownership

Proxmox owns certificate issuance and renewal through its built-in ACME client. DNS-01 is required because the management interface remains private; do not expose the Proxmox UI to the public internet to satisfy HTTP-01.

Create a dedicated Bitwarden Secrets Manager item named `PVE_ACME_CLOUDFLARE_API_TOKEN`. Its Cloudflare token needs `Zone:DNS:Edit` and `Zone:Zone:Read`; prefer scoping both permissions to `bohdal.name` only. Do not reuse the shared `CLOUDFLARE_API_TOKEN`, cert-manager credentials, or any other workload token. Do not commit, print, encode in observable output, or pass the token on a command line.

An authorized Proxmox administrator must create a Cloudflare DNS ACME plugin in **Datacenter → ACME**, enter the dedicated token through the UI, and include the immutable `bohdal.name` Cloudflare zone ID as `CF_Zone_ID` when the provider supports it. The zone ID is not a credential; supplying it avoids unreliable automatic zone discovery. Configure `pve.bohdal.name` and `pve.sk.bohdal.name` as node ACME domains using that plugin. First order against Let's Encrypt staging, inspect the resulting DNS-01 challenge, then change to the production directory and order the production certificate. Proxmox stores the protected plugin configuration in its node-private cluster filesystem and renews the installed `pveproxy` certificate automatically.

Keep PVE and `libproxmox-acme-*` packages aligned before debugging DNS provider behavior. The initial PVE 9.0 package set did not successfully issue with the Cloudflare token flow; PVE 9.2 with `libproxmox-acme-perl` and `libproxmox-acme-plugins` 1.7.2 was used for the successful staging and production orders. If Cloudflare access is temporarily broadened to issue a certificate, validate a staging order after returning it to `bohdal.name` only before relying on unattended renewal.

If a token is ever displayed, encoded in a log, included in terminal output, or copied into an untrusted location, revoke it and remove the corresponding Proxmox plugin configuration before creating a replacement. For the shared `CLOUDFLARE_API_TOKEN`, first update and verify every consumer, then revoke the exposed token last. For the dedicated PVE token, replace the plugin credential and validate a staging order before revoking its predecessor.

## Verification and rollback

After the production order completes, confirm from a LAN client that both `https://pve.bohdal.name:8006/` and `https://pve.sk.bohdal.name:8006/` present a chain trusted by the operating-system browser store and include both names as DNS subject alternative names. Confirm the internal A and PTR answers through Blocky, then reconcile Flux and require the Proxmox exporter scrape to remain `up=1` with TLS verification enabled.

If issuance or exporter verification fails, keep the node hostname unchanged, restore the previous split-DNS and exporter references to `pve.sk.bohdal.name`, and restore the known-working PVE proxy certificate before retrying. Never disable TLS verification as a rollback shortcut.
