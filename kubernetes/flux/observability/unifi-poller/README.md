# UniFi Poller

This component runs the maintained `unpoller/unpoller` exporter in Prometheus mode against the restored UniFi controller so controller, site, device, and client summaries are available without duplicating the AP SNMP dashboards.

Bitwarden Secrets Manager item `SK-TALOS-UNIFI-POLLER-USERNAME` (`675e9847-f554-429b-82b8-b4b70093713d`) contains only the controller login name `unifi-poller-api`, and item `SK-TALOS-UNIFI-POLLER-PASSWORD` (`885119a8-1efa-4b04-95f5-b4b700937198`) contains only the matching password.

The Flux stage starts suspended. Create the Kubernetes Secret before resuming it:

```sh
set +x
export UNIFI_POLLER_USERNAME="$(bws secret get 675e9847-f554-429b-82b8-b4b70093713d -o json | jq -r .value)"
export UNIFI_POLLER_PASSWORD="$(bws secret get 885119a8-1efa-4b04-95f5-b4b700937198 -o json | jq -r .value)"

kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace observability --dry-run=client -o yaml \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability create secret generic unifi-poller-auth \
  --from-literal=UP_UNIFI_DEFAULT_USER="${UNIFI_POLLER_USERNAME}" \
  --from-literal=UP_UNIFI_DEFAULT_PASS="${UNIFI_POLLER_PASSWORD}" \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

unset UNIFI_POLLER_USERNAME UNIFI_POLLER_PASSWORD
```

Keep shell tracing disabled while either credential is present.

Resume and reconcile the Flux stage after the Secret exists:

```sh
flux resume kustomization observability-unifi-poller -n flux-system
flux reconcile kustomization observability-unifi-poller -n flux-system
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability wait deployment/unifi-poller --for=condition=Available --timeout=5m
```

The dashboard in this component focuses on controller-side health and client summaries. AP radio and channel details remain on the SNMP dashboards.

## Validation

Render and validate the component before reconciliation:

```sh
kubectl kustomize kubernetes/flux/observability/unifi-poller
kubectl kustomize kubernetes/flux/observability/unifi-poller | kubectl apply --server-side --dry-run=server -f -
```

After reconciliation, require the Deployment and Service to be Ready, the exporter `/metrics` endpoint to answer through the Service, the controller login to use the dedicated read-only local account, and the dashboard and alert rule to appear in Grafana and VMAlert without exposing credential values.

Rollback leaves the manually bootstrapped Secret in place. Suspend or revert the Flux Kustomization separately if rollback requires reconciliation to stop.
