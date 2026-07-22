# Cloudflare Tunnel Connector

This component runs two fixed `cloudflared` 2026.7.2 replicas for the remotely managed shared `sk-talos` tunnel. The replicas provide process and rollout redundancy; preferred anti-affinity will spread them across nodes when another schedulable worker exists.

The Cloudflare control-plane stack routes only `grafana.bohdal.name` through these connectors and leaves a terminal `404` rule for every unmatched hostname. Deploying the connector alone still cannot publish an application; public DNS, tunnel ingress, and Access remain OpenTofu-owned resources.

## Token bootstrap

Bitwarden Secrets Manager item `SK-TALOS-CLOUDFLARED-TOKEN` (`03507e72-7537-4349-8b43-b48a009a9608`) contains only the connector token.

Create the Kubernetes Secret before Flux reconciles this component:

```bash
export CLOUDFLARED_TOKEN="$(bws secret get 03507e72-7537-4349-8b43-b48a009a9608 -o json | jq -r .value)"

kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace cloudflare-tunnel --dry-run=client -o yaml \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cloudflare-tunnel create secret generic tunnel-token \
  --from-literal=token="${CLOUDFLARED_TOKEN}" \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

unset CLOUDFLARED_TOKEN
```

The token is passed through the `TUNNEL_TOKEN` environment variable rather than command-line arguments, keeping it out of process listings. Restart the Deployment after rotating the Secret.

## Validation

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cloudflare-tunnel rollout status deployment/cloudflared
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cloudflare-tunnel get pods -o wide
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cloudflare-tunnel logs deployment/cloudflared
```

Both pods must be Ready and report registered tunnel connections. Validate public hostname routing and Cloudflare Access through the OpenTofu stack's acceptance procedure rather than mutating the remotely managed tunnel in the dashboard.
