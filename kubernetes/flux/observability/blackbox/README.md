# Blackbox Exporter

This component installs Prometheus Blackbox Exporter 0.28.0 as a single ClusterIP-only multi-target prober. It initially checks the MikroTik gateway with IPv4 ICMP and resolves `gw.bohdal.name` through the real Blocky LoadBalancer VIP, requiring the expected split-DNS address.

Grafana HTTPS probing is added only after its browser-trusted LAN endpoint exists. A stable external HTTPS endpoint also remains pending explicit selection. Moonraker and outside-cluster path probes are deferred by design.

The pod runs without a service-account token, uses a read-only filesystem, and receives only `NET_RAW` for ICMP. Cilium policy admits HTTP access from VMAgent and kubelet health probes, permits ICMP only to `10.1.100.1`, and permits DNS only to `10.1.30.53` on UDP/TCP port 53.

## Validation

Render and validate the component:

```sh
kubectl kustomize kubernetes/flux/observability/blackbox
kubectl kustomize kubernetes/flux/observability/blackbox | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require a Ready pod with no repeated restarts, `up=1` for the exporter self-scrape, `probe_success=1` for both logical instances, the expected DNS answer, and no unexpected egress flows.

Routine rollback suspends or reverts the `observability-blackbox` Flux Kustomization. The component owns no persistent storage or Secrets.
