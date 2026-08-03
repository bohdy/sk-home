# MikroTik gateway certificate

This stack owns the trusted certificate served by the MikroTik gateway at `gw.bohdal.name`. Internal CoreDNS owns the forward and reverse records; Cloudflare hosts the public zone only for ACME DNS-01 challenges. DNS-01 permits automatic renewal without opening port 80, changing the Cloudflare proxy, or making the RouterOS management plane publicly reachable.

The ACME account key, certificate private key, and RouterOS import payload are sensitive OpenTofu values stored only in the encrypted Cloudflare R2 state. They must never be added to Bitwarden, GitHub artifacts, Kubernetes Secrets, command lines, logs, or outputs.

The pinned RouterOS provider cannot safely adopt the gateway's built-in `www-ssl` service because the REST API returns duplicate service names with unstable IDs. It also cannot reliably find a certificate immediately after REST import because RouterOS generates its own certificate name. The stack therefore uses documented RouterOS REST file and execute endpoints as a narrow break-glass installer: it creates temporary files and writes the ACME leaf, its immediate issuer, and key through `POST /rest/execute`, imports them with checked `POST /rest/certificate/import` actions, renames the exact private-key leaf by its public fingerprint with `PATCH /rest/certificate/{id}`, and removes the temporary files. RouterOS rejects file contents in the REST `PUT /file` body on this device, and also rejects the full multi-certificate issuer bundle, so the installer uses one execute call per file and keeps only the first intermediate; clients validate the remaining chain to their roots. Certificate selection treats RouterOS's string-valued `expired` and `invalid` flags as booleans, so an unusable object can never be bound. A separate reconciliation action runs on every certificate workflow invocation; it selects the newest unexpired, valid private-key certificate for `gw.bohdal.name`, reads the one addressed `www-ssl` listener, and updates that returned ID through the provider-compatible `POST /rest/ip/service/set` action. The action accepts RouterOS's array-shaped success response and retries both the update and read-back while the HTTPS listener restarts. It changes no other certificate or service and never logs private material.

The authoritative `dns.bohdal.name` server publishes DNS-01 TXT records after the ACME provider's default check window. `propagation_wait = 300` waits five minutes before validation so the weekly renewal run uses the same verified authoritative DNS path.

RouterOS imports each PEM certificate as a separate certificate object. The installer imports the ACME intermediate and leaf separately under stable unique names. Each renewal removes only the previous objects with those names before importing the replacement. Bootstrap explicitly replaces the installer resource once so legacy dynamically named chain objects cannot remain the preferred binding. The weekly reconciliation also repairs service drift when ACME has not issued a new leaf, prefers the stack-owned leaf name, and rejects expired certificate objects before selecting the listener certificate.

## Bootstrap and renewal

The current gateway certificate expired before this stack was introduced. The first reviewed production apply must set `bootstrap_gateway_certificate=true` solely to replace or recover that expired HTTPS listener. During this explicitly approved recovery, the workflow uses the gateway's private `http://10.1.100.1/` REST endpoint so the provider can repair a listener that cannot complete TLS; credentials remain inside the private management path. Thereafter leave it `false`: the provider verifies `gw.bohdal.name` normally over HTTPS.

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
