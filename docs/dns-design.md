# DNS design

This file records the current DNS design decisions so the Kubernetes implementation can be changed deliberately later.

## Goal

Run the home DNS path on Kubernetes with a stable BGP-advertised service address. LAN clients should use one DNS endpoint that provides internal `bohdal.name` resolution, query visibility, local policy overrides, caching, and protected upstream resolution.

## Traffic flow

LAN clients query Blocky at `10.1.30.53`. Blocky forwards to CoreDNS inside the cluster. CoreDNS serves the internal `bohdal.name` zone and forwards public recursion to DNS4EU Protective + Ad Blocking over DNS-over-TLS.

```text
LAN client -> Blocky LoadBalancer VIP 10.1.30.53 -> CoreDNS -> DNS4EU DoT noads.joindns4.eu
```

## Kubernetes exposure

Blocky is the only DNS service exposed to LAN clients. It should run with at least two replicas and use a stable LoadBalancer VIP reserved from the existing Cilium service pool.

The chosen client-facing DNS VIP is `10.1.30.53`. Cilium already advertises LoadBalancer service VIP host routes from `10.1.30.0/24` to the MikroTik gateway over BGP, so the DNS service should fit into that existing routing model instead of introducing a separate BGP speaker.

The Blocky `LoadBalancer` service should request `10.1.30.53` with Cilium LB IPAM annotation `lbipam.cilium.io/ips`. Leave `spec.loadBalancerIP` unset unless implementation testing shows the annotation is unavailable for the installed Cilium version. Leave `loadBalancerClass` unset while Cilium is the default LoadBalancer allocator.

CoreDNS should stay internal to the cluster behind a `ClusterIP` service unless a later requirement needs direct LAN access.

The DNS stack should be deployed with plain Kubernetes manifests reconciled by Flux. Helm should be deferred until the raw manifests become repetitive or a chart provides clear operational value.

DNS resources should live in a dedicated `dns-system` namespace.

Label the `dns-system` namespace for baseline Pod Security Admission at enforce, warn, and audit levels. Bring-up testing showed the pinned upstream Blocky and CoreDNS images fail before application startup under restricted PSA because `allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]` block their packaged executables. Treat returning this namespace to restricted PSA as a follow-up that requires cap-free images or another validated image strategy.

Blocky should expose classic DNS on both UDP/53 and TCP/53 to LAN clients. DoH and DNS-over-TLS should not be exposed to LAN clients in the first version. The encrypted DNS boundary for now is CoreDNS to DNS4EU over DNS-over-TLS.

The design should be IPv6-ready, but the first implementation is IPv4-only. Do not add AAAA records or IPv6 service VIPs until real reachable IPv6 addresses, Cilium LB IPAM pools, BGP advertisement policy, firewall rules, and client advertisement behavior are decided and working. Use IPv4 `SingleStack` services in the first implementation. When IPv6 service pools and routing exist, change service family policy deliberately as part of a separate dual-stack task.

Blocky should use `externalTrafficPolicy: Local` on the client-facing `LoadBalancer` service so Blocky can see real LAN client source IPs for logs and client-aware policy. Before implementation, verify that Cilium's LoadBalancer/BGP behavior avoids advertising unusable local endpoints for this service.

Leave Blocky `internalTrafficPolicy` as the default `Cluster`; the source-IP requirement applies to LAN clients entering through the LoadBalancer, not to internal cluster callers.

Blocky should also expose its HTTP/API/metrics listener only inside the cluster through a separate `ClusterIP` service. It must not be published on the LAN DNS VIP. Enable Prometheus metrics on this internal listener now so future observability can scrape it.

Prefer metrics-only or read-only HTTP/API exposure if the selected Blocky version supports that cleanly. If the HTTP listener exposes mutable controls without authentication, keep it cluster-internal with NetworkPolicy and revisit auth/RBAC before any broader exposure.

Both Blocky and CoreDNS should run two replicas. Replicas should be spread across nodes with topology spread on `kubernetes.io/hostname`. DNS pods may run on any stable Linux node, including control-plane nodes. If worker nodes are added later, worker preference may be added as a soft preference, but DNS should not require workers unless the availability tradeoff is explicitly accepted.

DNS pods should explicitly tolerate standard control-plane taints so they can schedule on the current Talos control-plane nodes. Use normal pod networking, not `hostNetwork`; source IP preservation should come from the Blocky LoadBalancer service using `externalTrafficPolicy: Local`.

Add one `PodDisruptionBudget` for Blocky and one for CoreDNS with `minAvailable: 1`. Deployments should use rolling updates with `maxUnavailable: 0` and `maxSurge: 1`.

ConfigMap changes should trigger automatic pod rollouts through checksum annotations on pod templates. Do not add a cluster-wide reloader controller for this first DNS stack.

Add a shared cluster-scoped `PriorityClass` named `sk-home-critical` in a cluster policy component, not inside the DNS component. Use value `1000000`, `globalDefault: false`, and describe it as priority for critical home infrastructure services such as DNS. Blocky and CoreDNS should use `priorityClassName: sk-home-critical`.

Do not enable session affinity on the Blocky service initially. Blocky and CoreDNS should each use independent per-pod caches rather than shared cache or state.

Containers should run as non-root on high internal ports, with Kubernetes Services mapping client-facing port 53 to the unprivileged container ports. The pod security context should keep `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and `seccompProfile.type: RuntimeDefault`. Do not set `allowPrivilegeEscalation: false` or `capabilities.drop: ["ALL"]` for the pinned upstream DNS images until a replacement image path is validated, because that combination currently makes the binaries fail with `operation not permitted`. Writable `emptyDir` mounts should be added only where an image needs scratch space.

Use dedicated Kubernetes `ServiceAccount`s with no RBAC for Blocky and CoreDNS. Set `automountServiceAccountToken: false` on pods unless a component proves it needs Kubernetes API access.

Container images should be pinned by immutable digest, with comments or nearby documentation recording the human-readable version. Image updates should be manual digest bumps reviewed through pull requests until validation and observability are mature enough for automation.

DNS pods should have modest resource requests and memory limits. Avoid tight CPU limits initially so DNS latency is not throttled during bursts. A starting point is `25m` CPU and `64Mi` memory requests with a `128Mi` memory limit, then tune after metrics exist.

## Client configuration

MikroTik DHCP should hand out `10.1.30.53` directly as the DNS server for LAN clients. MikroTik should not remain in the normal client DNS forwarding path, although the router itself may use `10.1.30.53` for its own resolution.

The MikroTik DHCP change should be a follow-up after the Kubernetes DNS VIP is deployed and validated. First validation should use `dig @10.1.30.53` from at least one LAN client on each relevant VLAN.

Document rollback before changing DHCP. Before DHCP points clients at `10.1.30.53`, rollback is removing or disabling the DNS manifests. After DHCP changes, rollback must also restore the previous DHCP DNS option.

## Blocky responsibilities

Blocky is the front DNS service. It should provide client-facing query handling, query logging, client visibility, caching, and local allow/deny overrides. Blocky should not duplicate large public ad-block lists at the start; broad protective and ad-block filtering is delegated to the DNS4EU upstream path through CoreDNS.

`bohdal.name` should bypass Blocky ad filtering and local block policies so internal service discovery remains predictable. Any public fallback for `bohdal.name` should also bypass Blocky ad filtering.

Blocky should forward all DNS queries to CoreDNS as its default upstream. Do not add separate Blocky upstream groups for `bohdal.name` or public recursion; CoreDNS owns that split. Blocky should only define the bypass behavior needed to keep `bohdal.name` out of local blocking and deny rules. Blocky resolver entries use `[net:]host:[port]` syntax, so the CoreDNS upstream should be written as `tcp+udp:coredns.dns-system.svc.cluster.local:53`, not URL-style `tcp+udp://...`.

Local Blocky allow/deny overrides should apply before forwarding to CoreDNS. Deny overrides should return NXDOMAIN initially. Support exact and wildcard override entries if Blocky's config format makes that straightforward, but keep the initial override files empty. Add comments explaining exact versus wildcard syntax and noting that `bohdal.name` is intentionally excluded from deny policy.

Blocky should write logs to stdout only in the first implementation. Persistent DNS query log storage should wait for the observability stack because DNS logs can expose sensitive client behavior.

During bring-up, Blocky may log full query details and source IPs to stdout. Do not persist or ship those logs to long-term storage until the observability stack has an explicit retention and privacy decision. Client names can be added later from DHCP leases, static mappings, or broader reverse DNS; initial logs should use source IPs.

No custom public blocklists should be configured in Blocky initially. Empty documented allow/deny override files or config sections should be committed so future local overrides have an obvious place to live without adding fake active entries.

Blocky should cache DNS responses for client-facing latency and repeated LAN queries. Keep cache TTLs modest while iterating, around five minutes. Negative responses should be cached only briefly, around 30-60 seconds, so new internal records do not appear broken for long after being added.

## CoreDNS responsibilities

CoreDNS is authoritative for the internal `bohdal.name` zone. Internal records for `bohdal.name` should be committed in Git and reconciled by Flux with the rest of the Kubernetes add-ons.

If the internal `bohdal.name` authority is unavailable or does not answer, the intended fail-open behavior is public resolution for `bohdal.name` through the upstream resolver path.

CoreDNS is also responsible for forwarding non-local public DNS recursion to DNS4EU.

This CoreDNS instance must be separate from the cluster's built-in `kube-system` CoreDNS. The built-in Kubernetes DNS service should not be modified for LAN/internal DNS.

The separate CoreDNS instance should resolve only the internal `bohdal.name` zone, reverse DNS zones, and public recursion. It should not expose Kubernetes service discovery names such as `*.svc.cluster.local` to LAN clients.

CoreDNS should also cache responses, with modest TTLs while iterating. The CoreDNS cache primarily reduces repeated upstream recursion and smooths internal zone lookups.

Expose CoreDNS DNS on a `ClusterIP` service for Blocky. Keep CoreDNS health and readiness ports pod-only for probes. Enable CoreDNS metrics with the `prometheus` plugin on an internal pod port, but do not create a metrics Service until the observability stack or scraping convention exists.

## Upstream resolver

CoreDNS should use DNS4EU Protective + Ad Blocking as the public upstream resolver. The preferred encrypted upstream is DNS-over-TLS endpoint `noads.joindns4.eu`.

DNS4EU documents the Protective + Ad Blocking resolver as:

- IPv4: `86.54.11.13`
- IPv4 secondary: `86.54.11.213`
- DNS-over-HTTPS: `https://noads.joindns4.eu/dns-query`
- DNS-over-TLS: `noads.joindns4.eu`

Use the DNS4EU public resolver documentation as the source of truth before implementation because resolver endpoints and terms may change.

Configure CoreDNS with the DNS4EU IPv4 addresses as DoT upstream targets and `tls_servername noads.joindns4.eu`. Do not make CoreDNS resolve the upstream hostname before it can reach upstream DNS. Use both documented IPv4 endpoints with `policy round_robin`.

Do not enable local DNSSEC validation initially. Future DNSSEC work should evaluate CoreDNS validation first because CoreDNS owns public recursion. Blocky DNSSEC validation should stay deferred unless it provides a concrete benefit.

## Split DNS

The internal DNS zone is `bohdal.name`. Public records for the same domain are hosted outside the cluster, while CoreDNS serves the internal view inside the LAN. This is a split-DNS design.

CoreDNS should be treated as authoritative for the internal view of `bohdal.name`. Public fallback is allowed by design when the internal path cannot answer, but the implementation must make that behavior explicit and testable.

The initial forward records should include:

- `dns.bohdal.name. A 10.1.30.53`
- `blocky.bohdal.name. A 10.1.30.53`
- `gw.bohdal.name. A 10.1.100.1`

Do not add initial AAAA records until reachable IPv6 addresses exist.

The zone should include coherent SOA and NS records, using `dns.bohdal.name` as the internal nameserver identity. Start with a low TTL such as 300 seconds while the design is still changing.

Do not publish `coredns.bohdal.name` to LAN in the first implementation because CoreDNS is intentionally internal-only.

Reverse DNS should always be created for committed infrastructure records. The initial reverse records should include:

- `53.30.1.10.in-addr.arpa. PTR dns.bohdal.name.`
- `1.100.1.10.in-addr.arpa. PTR gw.bohdal.name.`

Broader reverse-zone coverage can be added as more internal records are committed.

CoreDNS DNS data should live in separate RFC-style zone files mounted into CoreDNS. The Corefile should contain resolver behavior and plugin wiring, not inline DNS records. Store the Corefile and zone files in separate ConfigMaps so behavior changes and DNS data changes can be reviewed independently.

SOA serials should be generated at render or commit time, not mutated at runtime. Add a small Python script using only the standard library in the first DNS implementation. By default, the script should use Git detection to update only zone files whose substantive DNS data changed, ignoring the existing serial during comparison. It should also support an explicit file list for CI or unusual workflows. Serial format should be date-based, `YYYYMMDDNN`.

The SOA serial script should be part of normal validation. Local update mode should rewrite stale serials. CI check mode should fail if zone data changed but rendered serials or manifests are stale.

Use a small repo-local render and validation step rather than an in-cluster Flux render step or a reloader controller. Flux should apply committed rendered manifests.

Keep DNS source and rendered output under the existing Flux infrastructure tree:

```text
kubernetes/flux/infrastructure/dns/
  README.md
  src/
  rendered/
scripts/render-dns.py
```

The `src/` tree should use mostly normal Kubernetes YAML with placeholders only where rendering is needed, such as checksums and generated values. Zone files should stay as plain RFC-style zone files. The render script should copy source to rendered, update SOA serials, inject config checksums, and support a check mode for CI.

Rendered manifests are generated output only. Humans should edit `src/`, zone files, and render scripts, not the rendered manifests. CI should fail if rendered output does not match source.

Validation should be wired into both local tooling and GitHub Actions immediately. Add separate `mise` tasks for rendering and checking:

```toml
[tasks.dns-render]
run = "python3 scripts/render-dns.py"

[tasks.dns-check]
run = "python3 scripts/render-dns.py --check"
```

The check path should verify render drift and run `kubectl kustomize` against `kubernetes/flux/infrastructure/dns/rendered`. Add `kubectl` to `mise.toml` instead of installing it directly on the host.

Add a local `pre-commit` hook that runs the DNS check and only fails on drift; it should not auto-update rendered files during commit. Developers should run the explicit render task when generated files need updating.

Add a separate lightweight GitHub Actions workflow for DNS validation, such as `.github/workflows/dns.yaml`. It should not share the Terraform workflow because DNS validation does not need Terraform secrets or backend access. Run the workflow on PRs and pushes for DNS-related paths, `scripts/render-dns.py`, `.github/workflows/dns.yaml`, and `mise.toml`.

## Flux reconciliation

The DNS implementation should restructure the current simple Flux infrastructure aggregation into Flux-level `Kustomization` resources so dependencies are explicit.

The root cluster path should apply orchestration objects under `kubernetes/flux/clusters/sk-talos/infrastructure/`. Shared cluster policy should have a Flux `Kustomization` named `cluster-policy`, Cilium should move behind a Flux `Kustomization` named `cilium`, and DNS should have its own Flux `Kustomization` named `dns` with `dependsOn` pointing to both `cluster-policy` and `cilium`.

Expected shape:

```text
kubernetes/flux/clusters/sk-talos/infrastructure/
  kustomization.yaml
  cluster-policy-kustomization.yaml
  cilium-kustomization.yaml
  dns-kustomization.yaml
kubernetes/flux/infrastructure/cluster-policy/
kubernetes/flux/infrastructure/cilium/
kubernetes/flux/infrastructure/dns/
  README.md
  src/
  rendered/
```

Cluster policy, Cilium, and DNS Flux `Kustomization` objects should use `prune: true`, `wait: true`, `interval: 10m`, and `retryInterval: 1m`. DNS Flux readiness should wait for Kubernetes resources such as Deployments to become ready.

## Health checks

Kubernetes readiness should be local-chain only and must not depend on DNS4EU or other public upstream availability because an upstream outage should not remove otherwise healthy local DNS pods from service.

Do not add a synthetic DNS health CronJob in the first implementation. It adds an extra image, script, policy surface, and failure semantics before the observability stack exists. DNS-level validation should start as documented manual smoke tests using `dig @10.1.30.53` from LAN clients. Add synthetic monitoring later with the observability stack, where alerting, retention, and notification routing can be designed together.

Keep application images minimal and do not require `dig` or similar DNS tools inside the Blocky and CoreDNS containers.

CoreDNS should use the `health` plugin for liveness and the `ready` plugin for readiness. Do not add a sidecar solely for DNS query readiness. Keep CoreDNS health and readiness endpoints internal to the pod or cluster, not exposed on the LAN.

Blocky readiness should use a TCP socket probe against its DNS listener. Blocky liveness should use a conservative TCP socket probe with a longer initial delay and failure threshold. Use an HTTP health probe only if the chosen Blocky version documents a stable health endpoint.

Manual smoke tests should cover UDP and TCP queries to the Blocky VIP, expected internal A records, expected PTR records, public resolution for `www.bohdal.name`, and public resolution for a neutral stable external domain such as `example.com`. Do not assert exact public IPs for public names. Do not test DNS4EU filtering behavior in the first implementation; add a filtering test later only if DNS4EU documents a stable test domain for that purpose.

## Network policy

Add minimal enforcing `NetworkPolicy` resources in the first implementation. The policies should keep the DNS traffic shape explicit without trying to model future observability before it exists.

The first policy set should allow ingress to Blocky on UDP/TCP 53 from clients that can route to the service VIP, allow Blocky HTTP/API/metrics only inside the cluster, allow CoreDNS UDP/TCP 53 only from Blocky pods, allow Blocky egress to CoreDNS UDP/TCP 53, and allow CoreDNS egress to DNS4EU on TCP 853. Additional egress should be added only if the manifests require it.

Keep Blocky's internal HTTP/API/metrics service broadly reachable inside the cluster for the first version, but not reachable from LAN. Tighten it to an observability namespace later when that namespace and scraping pattern exist. Defer specific CoreDNS metrics NetworkPolicy until there is a metrics Service or observability namespace.

At the NetworkPolicy layer, allow all ingress to Blocky UDP/TCP 53 rather than trying to model LAN CIDRs with `ipBlock`. LAN reachability should be controlled by router/firewall policy. Restrict CoreDNS egress to DNS4EU's documented IPv4 addresses on TCP 853. If DNS4EU changes those addresses, update both CoreDNS configuration and NetworkPolicy.

Use a default-deny posture for DNS pod egress, including no Kubernetes API egress by default. If a future feature needs API access, add RBAC, service-account token mounting, and NetworkPolicy egress deliberately.

## Remaining follow-up

The Kubernetes DNS manifests, render workflow, validation wiring, and documentation are now represented in the repository. The MikroTik DHCP change that hands out `10.1.30.53` remains a follow-up after the Kubernetes DNS VIP is deployed and validated from LAN clients.
