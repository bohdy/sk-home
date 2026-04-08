# DNS Blocky k3s

This stack deploys a dedicated Blocky DNS forwarder for the new k3s cluster with one pod per node (`DaemonSet`) and a fixed MetalLB IP for LAN DNS clients.

## What This Stack Owns

- Blocky namespace, rendered ConfigMap, query-log PVC, and DaemonSet.
- External `LoadBalancer` DNS service on `53/TCP+UDP` for clients.
- Internal `ClusterIP` metrics service on `:4000` for vmagent scraping.
- Git-managed local records, upstreams, and denylist settings.

## Operational Notes

- Keep local DNS records and blocking policy in this stack variables/config instead of UI-only edits so Terraform remains source of truth.
- Query logs can contain sensitive domain/client metadata; keep `log.privacy = true`, control retention, and avoid exporting raw logs to low-trust sinks.
- This stack intentionally uses a separate state key from legacy `dns-blocky` to preserve migration rollback options.

## Prerequisites

1. Load Terraform credentials from Bitwarden: `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"`.
2. Ensure `kubeconfig_path` points at the new k3s cluster.
3. Ensure `dns_ip` is free in the MetalLB pool advertised by `cluster-core-k3s`.
4. Disable Traefik DNS port exposure in `cluster-core-k3s` before applying this stack to avoid `:53` ownership conflicts.

## Canary Rollout

1. Apply this stack and verify `DaemonSet` readiness plus DNS answers on the configured LB IP.
2. Add one canary DHCP scope/VLAN to use the new DNS IP.
3. Validate query success, block behavior, latency, and metrics visibility.
4. Expand DNS assignment to remaining scopes after the canary window is stable.
