# Shared Cloudflare Tunnel

This OpenTofu stack owns the remotely managed `sk-talos` Cloudflare Tunnel and Grafana's public perimeter. It routes only `grafana.bohdal.name` to Grafana's in-cluster HTTPS Service, retains a terminal `http_status:404` rule, adopts the proxied public CNAME, and creates the self-hosted Cloudflare Access application.

The Access application allows one exact Gmail identity through the existing Google identity provider and then requires an independent Cloudflare Access MFA factor. Google is not relied on to emit an authentication-method claim. Unmatched identities have no allow policy and are denied by Access. Grafana's own login remains enabled behind Access.

Application routes, proxied DNS records, and Cloudflare Access applications remain owned by the workload change that introduces each public hostname. Grafana is the first planned route.

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

The imported CNAME previously targeted an unmanaged legacy tunnel. The first reviewed apply repoints it to the stack-owned tunnel without deleting the DNS record.
