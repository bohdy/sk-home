# Shared Cloudflare Tunnel

This plan-only OpenTofu stack creates the remotely managed `sk-talos` Cloudflare Tunnel. The base configuration contains only a terminal `http_status:404` rule, so creating the tunnel does not publish an application.

Application routes, proxied DNS records, and Cloudflare Access applications remain owned by the workload change that introduces each public hostname. Grafana is the first planned route.

## Credentials

Load backend and Cloudflare credentials from Bitwarden Secrets Manager without printing them:

```bash
export AWS_ACCESS_KEY_ID="$(bws secret get f1a17686-db90-4ae0-80aa-b43701584bab -o json | jq -r .value)"
export AWS_SECRET_ACCESS_KEY="$(bws secret get 31f0524c-b94e-4446-ba46-b43701586360 -o json | jq -r .value)"
export TF_VAR_cloudflare_account_id="$(bws secret get 34461539-ca00-4f0b-b7e0-b41b00c9c243 -o json | jq -r .value)"
export TF_VAR_cloudflare_api_token="$(bws secret get 535c2d90-8239-4f6b-a70f-b41b00c9d06c -o json | jq -r .value)"
```

The API token must be restricted to the account and tunnel-management permissions needed by this stack. DNS and Access permissions are introduced only when their corresponding resources are added.

## Workflow

```bash
tofu -chdir=terraform/cloudflare/tunnel init
tofu -chdir=terraform/cloudflare/tunnel validate
tofu -chdir=terraform/cloudflare/tunnel plan -out=tofuplan
tofu -chdir=terraform/cloudflare/tunnel apply tofuplan
rm -f terraform/cloudflare/tunnel/tofuplan
```

This stack is intentionally not auto-applied from `main`. Review its plan, apply it explicitly, then write the sensitive `connector_token` output into a dedicated Bitwarden item before creating the Kubernetes `cloudflared` Secret. Never print or commit the connector token.
