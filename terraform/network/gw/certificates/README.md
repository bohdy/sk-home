# MikroTik gateway certificate

This stack owns the trusted certificate served by the MikroTik gateway at `gw.bohdal.name`. Internal CoreDNS owns the forward and reverse records; Cloudflare hosts the public zone only for ACME DNS-01 challenges. DNS-01 permits automatic renewal without opening port 80, changing the Cloudflare proxy, or making the RouterOS management plane publicly reachable.

The ACME account key, certificate private key, and RouterOS import payload are sensitive OpenTofu values stored only in the encrypted Cloudflare R2 state. They must never be added to Bitwarden, GitHub artifacts, Kubernetes Secrets, command lines, logs, or outputs.

The pinned RouterOS provider cannot safely adopt the gateway's built-in `www-ssl` service because the REST API returns duplicate service names with unstable IDs. It also cannot reliably find a certificate immediately after REST import because RouterOS does not return the requested name. The stack therefore uses documented RouterOS REST file and execute endpoints as a narrow break-glass installer: it uploads the ACME issuer, leaf, and key as temporary files with REST `PUT`; replaces only its two named certificate objects; selects the new leaf for `www-ssl`; and removes the temporary files. It changes no other certificate or service and never logs private material.

The authoritative `dns.bohdal.name` server publishes DNS-01 TXT records after the ACME provider's default check window. `propagation_wait = 300` waits five minutes before validation so the weekly renewal run uses the same verified authoritative DNS path.

RouterOS imports each PEM certificate as a separate certificate object. The installer imports the ACME intermediate and leaf separately under stable unique names. Each renewal removes only the previous objects with those names before importing the replacement, then selects the leaf for `www-ssl` in the same apply.

## Bootstrap and renewal

The current gateway certificate expired before this stack was introduced. The first reviewed production apply must set `bootstrap_gateway_certificate=true` solely to replace that expired certificate. Thereafter leave it `false`: the provider verifies `gw.bohdal.name` normally.

Use the existing Bitwarden values for the RouterOS automation identity and Cloudflare DNS token, plus a new non-secret `TF_VAR_acme_email` contact address. The Cloudflare token must retain `Zone:DNS:Edit` and `Zone:Zone:Read` for `bohdal.name`.

The workflow checks the certificate every Monday at 03:17 UTC. `acme_certificate.gateway` renews automatically once fewer than 30 days remain, and the RouterOS certificate is then replaced in the same immutable plan. The binary plan is intentionally never uploaded because it can contain sensitive certificate material. The existing `production` environment remains the approval boundary; configure its approval policy to match the desired level of unattended renewal.

```sh
gh workflow run mikrotik-certificates.yaml --ref main \
  -f bootstrap_gateway_certificate=false
```

For the initial expired-certificate recovery only, change the final value to `true`. After each apply, verify that the LAN DNS A and PTR records still resolve and that HTTPS validates without `--insecure`:

```sh
dig @10.1.30.53 gw.bohdal.name A
dig @10.1.30.53 -x 10.1.100.1
curl --fail --resolve gw.bohdal.name:443:10.1.100.1 https://gw.bohdal.name/rest/system/resource -o /dev/null
```

The expected HTTPS response without credentials is `401`; TLS validation must succeed before that response. Do not print certificate or key material while troubleshooting.
