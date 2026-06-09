# Project memory

This file records operational facts and future-facing notes that should survive individual implementation threads. Keep entries concise, dated, and tied to concrete follow-up decisions.

## 2026-06-09 DNS bring-up

Flux bootstrap for the Talos cluster succeeded with Flux v2.8.8 under `kubernetes/flux/clusters/sk-talos`.

The LAN DNS design uses Blocky as the only client-facing resolver at `10.1.30.53` and CoreDNS as the internal split-DNS authority and DNS4EU DoT forwarder.

During live bring-up, the pinned upstream Blocky and CoreDNS images failed with `operation not permitted` when the DNS namespace used restricted Pod Security Admission and the containers set `allowPrivilegeEscalation: false` with `capabilities.drop: ["ALL"]`. The current working decision is to keep the `dns-system` namespace at baseline PSA while retaining non-root execution, read-only root filesystems, and RuntimeDefault seccomp. Returning DNS to restricted PSA needs a validated cap-free image strategy or another tested runtime approach.

Blocky v0.29 resolver entries use `[net:]host:[port]` syntax. The CoreDNS upstream must be `tcp+udp:coredns.dns-system.svc.cluster.local:53`, not URL-style `tcp+udp://...`.

Blocky special-use domain blocking must stay disabled while CoreDNS is the only upstream, otherwise private reverse zones return Blocky-generated NXDOMAIN responses before CoreDNS can answer LAN PTR records.

CoreDNS reached healthy state once the runtime constraints were relaxed. Blocky reached healthy state after the runtime fix and corrected upstream syntax; a live test showed successful resolution of `dns.bohdal.name` through CoreDNS.

## Observability Inputs

DNS observability should preserve client IPs because Blocky is intentionally exposed with `externalTrafficPolicy: Local`. Metrics and logs should keep that source-IP requirement visible when dashboards and alerts are designed.

Blocky already exposes an internal HTTP listener on port `4000` with Prometheus metrics enabled at `/metrics`. It is intentionally exposed only through a ClusterIP service and should not be published on the LAN DNS VIP.

CoreDNS has the `prometheus` plugin enabled on pod port `9153`, but no metrics Service exists yet. The initial design deliberately kept CoreDNS health, readiness, and metrics pod-local or cluster-internal until an observability stack defines scraping conventions.

DNS query logs currently go to stdout only. Do not add long-term DNS query log shipping until retention, access control, and privacy expectations are explicit, because DNS logs expose client behavior.

Manual smoke tests remain the first validation layer: UDP and TCP `dig` against `10.1.30.53`, internal A records, reverse PTR records, public `www.bohdal.name`, and a neutral public domain such as `example.com`.

## Observability Options To Evaluate

Use Prometheus Operator or another ServiceMonitor-compatible stack if the cluster observability path is Kubernetes-native. That path would likely add a metrics Service or PodMonitor for Blocky and CoreDNS and keep scrape access constrained by namespace and NetworkPolicy.

Use Grafana Alloy or an OpenTelemetry Collector if the stack should collect metrics and logs through one agent model. This may be useful if DNS stdout logs need selective parsing, redaction, sampling, or routing before storage.

Use Loki for short-retention DNS application logs only after deciding retention and privacy policy. Prefer labels such as namespace, app, pod, and node; avoid high-cardinality labels such as query name, client IP, or full answer.

Use alerting rules that distinguish local DNS failure from public upstream failure. Pod readiness should stay local-chain only; public DNS4EU issues should be separate alerts based on synthetic checks or resolver metrics, not readiness gates.

Add synthetic DNS monitoring later from the observability stack rather than as a standalone CronJob. Useful checks include `dns.bohdal.name A`, `gw.bohdal.name A`, reverse PTRs for `10.1.30.53` and `10.1.100.1`, `www.bohdal.name A`, `example.com A`, and both UDP and TCP query paths. Do not assert exact public IPs for public names.

When observability is introduced, revisit NetworkPolicy for Blocky HTTP metrics and CoreDNS metrics. The current first implementation allows Blocky HTTP inside the cluster and has no CoreDNS metrics Service; future policy should restrict scraping to the observability namespace or collector pods.

Keep DNS4EU filtering validation deferred unless DNS4EU documents a stable test domain for the Protective + Ad Blocking profile.
