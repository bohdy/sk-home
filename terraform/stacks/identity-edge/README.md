# Identity Edge

This stack replaces the Pulumi `sk-networking` domain with import-oriented Terraform.

It owns:

- the existing Cloudflare Zero Trust tunnel
- the remote tunnel ingress configuration
- the shared Access group and allow policy
- the in-cluster `cloudflared` namespace, token secret, and deployment

Import the live Cloudflare tunnel and Access resources before the first apply. The committed configuration expects the existing tunnel secret in base64 form so Terraform can preserve the live connector identity instead of rotating it.

Load credentials through [`load-bitwarden-secrets.sh`](/Users/bohdy/git/sk-home/scripts/load-bitwarden-secrets.sh). The Terraform profile can now materialize a kubeconfig file automatically when Bitwarden stores `KUBECONFIG_CONTENT`.
