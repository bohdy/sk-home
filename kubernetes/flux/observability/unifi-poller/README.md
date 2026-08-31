# UniFi Poller

This component runs the maintained `unpoller/unpoller` exporter in Prometheus mode against the restored UniFi controller so controller, site, and client summaries are available without duplicating the AP SNMP dashboards.

The `VMServiceScrape` drops every `unpoller_device_*` series so AP device coverage remains SNMP-owned while controller, site, and `unpoller_client_*` metrics remain available. The dashboard's connected-client panel uses `unpoller_client_rssi_db` and remains populated under this contract.

Bitwarden Secrets Manager item `SK-TALOS-UNIFI-POLLER-USERNAME` (`675e9847-f554-429b-82b8-b4b70093713d`) contains only the controller login name `unifi-poller-api`, and item `SK-TALOS-UNIFI-POLLER-PASSWORD` (`885119a8-1efa-4b04-95f5-b4b700937198`) contains only the matching password.

Create the Kubernetes Secret before activating the Flux stage. Run this block with Bash because it uses process substitution; `jq -j` emits each value without adding a trailing newline:

```bash
set +x

kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace observability --dry-run=client -o yaml \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability create secret generic unifi-poller-auth \
  --from-file=UP_UNIFI_DEFAULT_USER=<(bws secret get 675e9847-f554-429b-82b8-b4b70093713d -o json | jq -j .value) \
  --from-file=UP_UNIFI_DEFAULT_PASS=<(bws secret get 885119a8-1efa-4b04-95f5-b4b700937198 -o json | jq -j .value) \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
```

Keep shell tracing disabled while either credential is present.

Persistently activate the optional Flux child after the Secret exists. This is an explicit bootstrap step; after it is applied, the child Kustomization is managed by Flux and continues reconciling independently from the automatic observability parent:

```sh
kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply \
  -f kubernetes/flux/clusters/sk-talos/observability/unifi-poller-kustomization.yaml
```

Reconcile the Flux child after activation:

```sh
flux reconcile kustomization observability-unifi-poller -n flux-system --kubeconfig /tmp/sk-talos-kubeconfig
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability wait deployment/unifi-poller --for=condition=Available --timeout=5m
```

The dashboard in this component focuses on controller-side health and client summaries. AP radio and channel details remain on the SNMP dashboards.

## Validation

Render and validate the component before reconciling Flux:

```sh
kubectl kustomize kubernetes/flux/observability/unifi-poller
kubectl kustomize kubernetes/flux/observability/unifi-poller | kubectl apply --server-side --dry-run=server -f -
```

After reconciliation, require the Deployment and Service to be Ready, the exporter `/metrics` endpoint to answer through the Service, the controller login to use the dedicated read-only local account, and the dashboard and alert rule to appear in Grafana and VMAlert without exposing credential values.

Rollback leaves the manually bootstrapped Secret in place. Revert the Flux Kustomization or suspend it separately if rollback requires reconciliation to stop.
