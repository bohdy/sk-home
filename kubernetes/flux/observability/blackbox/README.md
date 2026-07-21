# Blackbox Exporter

This component installs Prometheus Blackbox Exporter 0.28.0 as a single ClusterIP-only multi-target prober. It checks the MikroTik gateway with IPv4 ICMP, resolves `gw.bohdal.name` through the real Blocky LoadBalancer VIP with the expected split-DNS answer, requests Grafana's health endpoint through its real LAN HTTPS VIP, and verifies external HTTPS through Cloudflare's fixed `1.1.1.1` anycast address.

The Grafana probe connects to `10.1.30.55` but supplies `grafana.bohdal.name` through Blackbox's `hostname` parameter. A success therefore proves the Cilium VIP, HTTP Host handling, TLS SNI, public certificate trust, and `/api/health` response without depending on pod DNS. The external probe connects to `https://1.1.1.1/` with `one.one.one.one` as Host and SNI, requiring a trusted certificate and HTTP 200 without adding DNS egress. Moonraker and outside-cluster path probes are deferred by design.

The pod runs without a service-account token, uses a read-only filesystem, and receives only `NET_RAW` for ICMP. Cilium policy admits HTTP access from VMAgent and kubelet health probes, permits ICMP only to `10.1.100.1`, permits DNS only through the `10.1.30.53` VIP to Blocky pods on their UDP/TCP container port 1053, permits Grafana HTTPS only through `.55:443` to chart-managed Grafana pods on port 3000, and permits external HTTPS only to `1.1.1.1/32`. The explicit backend rules are required because Cilium applies in-cluster LoadBalancer translation before egress policy.

## Validation

Render and validate the component:

```sh
kubectl kustomize kubernetes/flux/observability/blackbox
kubectl kustomize kubernetes/flux/observability/blackbox | kubectl apply --server-side --dry-run=server -f -
```

After Flux reconciliation, require a Ready pod with no repeated restarts, `up=1` for the exporter self-scrape, `probe_success=1` for all four logical instances, the expected DNS answer, valid Grafana and external TLS chains with HTTP 200 responses, and no unexpected egress flows.

Routine rollback suspends or reverts the `observability-blackbox` Flux Kustomization. The component owns no persistent storage or Secrets.
