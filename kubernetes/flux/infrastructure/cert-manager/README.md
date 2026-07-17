# cert-manager

This component installs cert-manager v1.20.1 from the upstream Jetstack OCI Helm chart. Flux manages the chart and its CRDs together. The dependent `certificates` component creates the production Let's Encrypt `ClusterIssuer`.

## Cloudflare token

Bitwarden Secrets Manager item `CLOUDFLARE_API_TOKEN` (`535c2d90-8239-4f6b-a70f-b41b00c9d06c`) contains the Cloudflare API token. The token must be limited to `Zone:DNS:Edit` and `Zone:Zone:Read` for the `bohdal.name` zone.

Create the Kubernetes Secret before reconciling the `certificates` component:

```bash
export CLOUDFLARE_API_TOKEN="$(bws secret get 535c2d90-8239-4f6b-a70f-b41b00c9d06c -o json | jq -r .value)"

kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

unset CLOUDFLARE_API_TOKEN
```

Keep shell tracing disabled while the token is present. The Secret is deliberately not committed. A `ClusterIssuer` resolves its referenced credentials from the cert-manager controller namespace, so the Secret must remain in `cert-manager`.

## Validation

Confirm the Helm release, controller deployments, and issuer are ready:

```bash
flux --namespace cert-manager get helmrelease cert-manager
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cert-manager get pods
kubectl --kubeconfig /tmp/sk-talos-kubeconfig get clusterissuer letsencrypt-production
```

Certificate issuance is validated when the first workload `Certificate` is added. Routine rollback may suspend or revert the Flux components, but must not delete issued TLS Secrets or the ACME account key without an explicit recovery plan.
