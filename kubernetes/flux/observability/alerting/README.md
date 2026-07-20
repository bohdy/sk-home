# Observability Alerting

This component adds metric coverage and local VMAlert rules that are not supplied by the pinned VictoriaMetrics Kubernetes stack. It scrapes all Flux controllers and the cert-manager controller, then evaluates sustained synthetic, Vector, VictoriaLogs, Flux reconciliation, and certificate-expiry conditions.

The upstream rules continue to own Kubernetes node and workload readiness, repeated crashes, PVC capacity, resource pressure, generic scrape failures, and VictoriaMetrics control-plane health. Talos intentionally hides scheduler and controller-manager metrics, so the metrics Helm release disables those default groups rather than allowing permanent false alerts.

Every local rule has an explicit `warning` or `critical` severity and a sustained `for` interval. Brother and Klipper are absent because intermittent targets must not page when powered off. Alert annotations contain stable component identity only and must never include DNS queries, log messages, community strings, authentication material, or other sensitive payloads.

Alertmanager currently retains alerts and silences but routes to `blackhole`. Telegram and Discord receivers are added only after their dedicated Bitwarden items and Kubernetes Secret exist. The committed grouping and inhibition behavior is designed to remain in place when those receivers are introduced.

## Validation

Render and validate both the alerting component and changed metrics release:

```sh
kubectl kustomize kubernetes/flux/observability/alerting
kubectl kustomize kubernetes/flux/observability/alerting | kubectl apply --server-side --dry-run=server -f -
kubectl kustomize kubernetes/flux/observability/metrics | kubectl apply --server-side --dry-run=server --force-conflicts -f -
```

Live acceptance requires operational scrape resources and VMRule status, all four Flux targets and cert-manager at `up=1`, no permanent scheduler or controller-manager alerts, successful VMAlert evaluations, correct warning/critical inhibition, and no unexpected active local alerts.

Routine rollback suspends or reverts `observability-alerting` and reverts the metrics Helm values. Do not delete Alertmanager's retained PVC when rolling back rules or routing.
