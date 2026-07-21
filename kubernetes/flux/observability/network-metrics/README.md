# Network Metrics

This component adds bounded VictoriaMetrics discovery for Cilium agents, the Cilium operator, Hubble, and Blocky. It does not own or expose those workloads. Cilium agent and operator endpoints remain pod-local, Hubble uses the chart-managed headless Service, and Blocky uses its cluster-internal HTTP Service.

The pinned Cilium bootstrap values enable agent and operator metrics plus only the Hubble `dns`, `drop`, and `tcp` families. They intentionally add no source, destination, pod, workload, IP, identity, or DNS-name context labels. This keeps the first-release series count predictable while retaining DNS outcome, drop reason, and TCP flag visibility.

## Upgrade

Cilium itself is bootstrap-managed rather than installed by Flux. After this change is merged, reconcile the committed values against the existing pinned release explicitly:

```sh
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.4 \
  --values kubernetes/bootstrap/cilium/values.yaml
```

Do not enable Cilium's Prometheus `ServiceMonitor` resources: this repository uses VictoriaMetrics Operator CRDs directly. Do not add Hubble context options without reviewing the resulting cardinality.

## Validation

Render and validate the Flux component before applying the Cilium upgrade:

```sh
kubectl kustomize kubernetes/flux/observability/network-metrics
kubectl kustomize kubernetes/flux/observability/network-metrics | kubectl apply --server-side --dry-run=server -f -
```

After reconciliation, require one healthy `up` series for every Cilium agent, one for the operator, one Hubble series per node, and both Blocky replicas. Confirm that `cilium_*`, `hubble_dns_*`, `hubble_drop_*`, `hubble_tcp_*`, and `blocky_*` metrics are queryable with stable `cluster="sk-talos"` and `site="sk"` labels. Record the resulting active-series counts before considering broader Hubble labels.

Rollback by reverting the Flux component and running the same pinned `helm upgrade` with the reverted bootstrap values. Temporary loss of these metrics is acceptable; Cilium datapath health must remain the rollout gate.
