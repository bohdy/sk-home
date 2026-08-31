# Project memory

This file records operational facts and future-facing notes that should survive individual implementation threads. Keep entries concise, dated, and tied to concrete follow-up decisions.

## 2026-08-03 Infrastructure verification rule

Do not infer live infrastructure state from naming conventions, archived configuration, a successful OpenTofu plan, or an unverified configuration reference. Before creating or applying a change that depends on existing infrastructure, obtain and record direct evidence for every prerequisite (for example, a RouterOS DHCP server, its address pool, VLAN interface, network options, and available lease address). A successful plan can validate syntax and state interactions without proving that an assumed live dependency exists or is correctly configured.

## 2026-06-09 DNS bring-up

Flux bootstrap for the Talos cluster succeeded with Flux v2.8.8 under `kubernetes/flux/clusters/sk-talos`.

The LAN DNS design uses Blocky as the only client-facing resolver at `10.1.30.53` and CoreDNS as the internal split-DNS authority and DNS4EU DoT forwarder.

During live bring-up, the pinned upstream Blocky and CoreDNS images failed with `operation not permitted` when the DNS namespace used restricted Pod Security Admission and the containers set `allowPrivilegeEscalation: false` with `capabilities.drop: ["ALL"]`. The current working decision is to keep the `dns-system` namespace at baseline PSA while retaining non-root execution, read-only root filesystems, and RuntimeDefault seccomp. Returning DNS to restricted PSA needs a validated cap-free image strategy or another tested runtime approach.

Blocky v0.29 resolver entries use `[net:]host:[port]` syntax. The CoreDNS upstream must be `tcp+udp:coredns.dns-system.svc.cluster.local:53`, not URL-style `tcp+udp://...`.

Blocky special-use domain blocking must stay disabled while CoreDNS is the only upstream, otherwise private reverse zones return Blocky-generated NXDOMAIN responses before CoreDNS can answer LAN PTR records.

CoreDNS reached healthy state once the runtime constraints were relaxed. Blocky reached healthy state after the runtime fix and corrected upstream syntax; a live test showed successful resolution of `dns.bohdal.name` through CoreDNS.

## 2026-08-31 UniFi controller polling

The dedicated `observability-unifi-poller` stage is prepared to export controller, device, and client metrics from the restored UniFi controller using the read-only local service account stored in Bitwarden. Secret bootstrap, Flux reconciliation, and live acceptance remain pending.

AP radio and channel detail stay on the SNMP dashboards, so the prepared controller-metrics dashboard only covers controller-side health and client summaries.

## 2026-07-16 observability design

The settled observability implementation contract is `docs/observability-design.md`. It supersedes earlier exploratory observability notes in this file; update the design document and relevant ADRs rather than duplicating detailed decisions here.

The first release uses the VictoriaMetrics Kubernetes stack, VictoriaLogs, Vector, Grafana, SNMP Exporter, Blackbox Exporter, VMAlert, and Alertmanager inside `sk-talos`. It requires a general-purpose worker and validated Synology CSI storage before stateful deployment.

Raw metrics retention is one year and log retention is 30 days. Traces, raw telemetry backups, an external dead-man monitor, Klipper monitoring, and automated Bitwarden secret reconciliation are tracked follow-ups.
