# Shared Cloudflare Tunnel

This OpenTofu stack owns the remotely managed `sk-talos` Cloudflare Tunnel plus Grafana's, UniFi's, and Second Brain's public perimeters. It routes `grafana.bohdal.name` to Grafana's in-cluster HTTPS Service and `unifi.bohdal.name` to UniFi's private console origin, retains a terminal `http_status:404` rule, manages their proxied public CNAMEs, and manages their self-hosted Cloudflare Access applications.

Each Access application allows the same one exact Gmail identity through the existing Google identity provider. Independent Cloudflare Access MFA is disabled, so the owner must enforce strong authentication on the Google account; unmatched identities have no allow policy and are denied by Access. Grafana's and UniFi's own logins remain enabled behind Access; Second Brain retains its API bearer authentication.

Application routes, proxied DNS records, and Cloudflare Access applications remain owned by the workload change that introduces each public hostname. Grafana, UniFi, and Second Brain are the declared routes. Second Brain uses `brain.bohdal.name` and the private HTTP origin `http://second-brain.second-brain.svc.cluster.local:8080`; the configurable `brain_hostname` and `brain_origin_service` defaults are committed in `variables.tf`. No internal DNS record, VIP, or RouterOS rule is added. Its Access application must exist before tunnel routing or its proxied CNAME can be published, enforced through explicit dependencies. The application continues requiring its own API bearer token behind Access.

## Credentials

Load backend and Cloudflare credentials from Bitwarden Secrets Manager without printing them:

```bash
export AWS_ACCESS_KEY_ID="$(bws secret get f1a17686-db90-4ae0-80aa-b43701584bab -o json | jq -r .value)"
export AWS_SECRET_ACCESS_KEY="$(bws secret get 31f0524c-b94e-4446-ba46-b43701586360 -o json | jq -r .value)"
export TF_VAR_cloudflare_account_id="$(bws secret get 34461539-ca00-4f0b-b7e0-b41b00c9c243 -o json | jq -r .value)"
export TF_VAR_cloudflare_api_token="$(bws secret get 535c2d90-8239-4f6b-a70f-b41b00c9d06c -o json | jq -r .value)"
```

The API token must be restricted to the account, zone, tunnel configuration, DNS record, Access application, and identity-provider read permissions needed by this stack.

Bitwarden item `SK-TALOS-GRAFANA-ACCESS-EMAIL` (`483e35d1-7bd1-46df-9946-b48f00b093d8`) contains exactly one normalized Gmail address. Load it without printing the value:

```sh
export TF_VAR_grafana_access_email="$(bws secret get 483e35d1-7bd1-46df-9946-b48f00b093d8 -o json | jq -r .value)"
```

## Workflow

```bash
tofu -chdir=terraform/cloudflare/tunnel init
tofu -chdir=terraform/cloudflare/tunnel validate
tofu -chdir=terraform/cloudflare/tunnel plan -out=tofuplan
tofu -chdir=terraform/cloudflare/tunnel apply tofuplan
rm -f terraform/cloudflare/tunnel/tofuplan
```

This stack is intentionally not auto-applied from `main`. After merging a reviewed change, dispatch `.github/workflows/terraform.yaml` with only `apply_cloudflare=true`; the production job applies the immutable Cloudflare plan artifact from that run. The connector token remains in its dedicated Bitwarden item and must never be printed or committed.

The initial migration repointed the existing CNAMEs from the unmanaged legacy tunnel to the stack-owned tunnel without deleting the DNS records.

## Second Brain staging and review gate

The Second Brain Flux child remains suspended. Preparing its Cloudflare resources does not activate the application or provision runtime secrets. The existing Bitwarden-backed `grafana_access_email` supplies the same exact owner identity for all three applications; no new owner credential is introduced. The tunnel receives only TCP 8080 access from the `cloudflare-tunnel` namespace, `cloudflared` pod label, and `cloudflared` service account. Direct API port 8000 and database port 5432 are excluded from that grant.

Backend-disabled initialization, validation, formatting, and manifest rendering are offline structural checks, not a Terraform plan. A real read-only plan against the authoritative backend and Cloudflare requires separately authorized credential access and is a prerequisite before committing or opening a pull request for this behavior change. The authorized credential-backed read-only plan passed on 2026-09-20 with exactly two creates (Second Brain Access application and proxied DNS record) and one update (shared tunnel configuration). Inspection verified the configured exact owner, private web origin, and unchanged existing routes. Planning used no remote lock; credential values remained in memory, raw plan/backend cache were removed after inspection, and only a sanitized summary was retained. No apply was performed. Existing production approval and immutable-plan workflow gates still apply to activation.
