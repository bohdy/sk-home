# Observability Alerting

This component adds metric coverage and local VMAlert rules that are not supplied by the pinned VictoriaMetrics Kubernetes stack. It scrapes all Flux controllers and the cert-manager controller, then evaluates sustained synthetic, Vector, VictoriaLogs, Flux reconciliation, and certificate-expiry conditions.

The upstream rules continue to own Kubernetes node and workload readiness, repeated crashes, PVC capacity, resource pressure, generic scrape failures, and VictoriaMetrics control-plane health. Talos intentionally hides scheduler and controller-manager metrics, so the metrics Helm release disables those default groups rather than allowing permanent false alerts.

Every local rule has an explicit `warning` or `critical` severity and a sustained `for` interval. Brother and Klipper are absent because intermittent targets must not page when powered off. Alert annotations contain stable component identity only and must never include DNS queries, log messages, community strings, authentication material, or other sensitive payloads.

Alertmanager retains all alerts and silences. Critical alerts route to Telegram and Discord with recovery messages; warnings route only to Discord, while info alerts terminate at `blackhole` and remain visible in Alertmanager and Grafana. Its pod mounts externally bootstrapped Secret `alertmanager-notifications` at `/etc/vm/secrets/alertmanager-notifications`; notification configuration uses Alertmanager's native file-backed secret fields rather than inline values or environment expansion.

Bitwarden items `TELEGRAM_BOT_TOKEN` (`b2ca02a3-d9b9-4d5b-ba5e-b41c00874fcf`), `TELEGRAM_CHAT_ID` (`e458b31f-4770-46d9-be92-b41c00880fc9`), and `SK-TALOS-DISCORD-WEBHOOK` (`306e8dc6-2df2-4a9e-86ec-b49000a691c7`) contain only their named values. The Kubernetes Secret must contain `telegram-bot-token`, `telegram-chat-id`, and `discord-webhook-url`; it is deliberately absent from Git.

Bootstrap or refresh the complete Secret with shell tracing disabled and without writing rendered Secret data to disk:

```sh
set +x
export TELEGRAM_BOT_TOKEN="$(bws secret get b2ca02a3-d9b9-4d5b-ba5e-b41c00874fcf -o json | jq -r .value)"
export TELEGRAM_CHAT_ID="$(bws secret get e458b31f-4770-46d9-be92-b41c00880fc9 -o json | jq -r .value)"
export DISCORD_WEBHOOK_URL="$(bws secret get 306e8dc6-2df2-4a9e-86ec-b49000a691c7 -o json | jq -r .value)"
kubectl -n observability create secret generic alertmanager-notifications \
  --from-literal=telegram-bot-token="${TELEGRAM_BOT_TOKEN}" \
  --from-literal=telegram-chat-id="${TELEGRAM_CHAT_ID}" \
  --from-literal=discord-webhook-url="${DISCORD_WEBHOOK_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID DISCORD_WEBHOOK_URL
```

The committed grouping and inhibition behavior applies before routes fan out. Critical alerts fan out to Telegram and Discord; warning alerts go only to Discord, and info alerts remain visible without push delivery.

The Cilium egress policy permits the shared pod network namespace to reach internal HTTPS/kube-apiserver ports for VictoriaMetrics config-init and config-reloader, resolve only `api.telegram.org` and `discord.com` through kube-dns, and reach only those FQDNs on TCP 443. The deliberately broad `10.0.0.0/8` internal destination boundary is required because Cilium enforces the translated Kubernetes Service backend and is accepted for this homelab.

## Validation

Render and validate both the alerting component and changed metrics release:

```sh
kubectl kustomize kubernetes/flux/observability/alerting
kubectl kustomize kubernetes/flux/observability/alerting | kubectl apply --server-side --dry-run=server -f -
kubectl kustomize kubernetes/flux/observability/metrics | kubectl apply --server-side --dry-run=server --force-conflicts -f -
```

Live acceptance requires operational scrape resources and VMRule status, all four Flux targets and cert-manager at `up=1`, no permanent scheduler or controller-manager alerts, successful VMAlert evaluations, correct warning/critical inhibition, no unexpected active local alerts, successful critical Telegram-and-Discord fan-out and warning Discord firing with resolved notifications, zero notification failures, and a successful config reload while egress policy is active.

Routine rollback suspends or reverts `observability-alerting` and reverts the metrics Helm values. Do not delete Alertmanager's retained PVC when rolling back rules or routing.
