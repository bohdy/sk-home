# Observability Alerting

This component adds metric coverage and local VMAlert rules that are not supplied by the pinned VictoriaMetrics Kubernetes stack. It scrapes all Flux controllers and the cert-manager controller, then evaluates sustained synthetic, Vector, VictoriaLogs, Flux reconciliation, and certificate-expiry conditions.

The upstream rules continue to own Kubernetes node and workload readiness, repeated crashes, PVC capacity, resource pressure, generic scrape failures, and VictoriaMetrics control-plane health. Talos intentionally hides scheduler and controller-manager metrics, so the metrics Helm release disables those default groups rather than allowing permanent false alerts.

Every local rule has an explicit `warning` or `critical` severity and a sustained `for` interval. Brother and Klipper are absent because intermittent targets must not page when powered off. Alert annotations contain stable component identity only and must never include DNS queries, log messages, community strings, authentication material, or other sensitive payloads.

Alertmanager currently retains alerts and silences but routes to `blackhole`. Its pod mounts externally bootstrapped Secret `alertmanager-notifications` at `/etc/vm/secrets/alertmanager-notifications`; notification configuration must use the mounted files rather than inline values or environment expansion. Egress is limited to cluster DNS plus HTTPS to `api.telegram.org` and `discord.com`.

Bitwarden items `TELEGRAM_BOT_TOKEN` (`b2ca02a3-d9b9-4d5b-ba5e-b41c00874fcf`) and `TELEGRAM_CHAT_ID` (`e458b31f-4770-46d9-be92-b41c00880fc9`) contain only their named values. Create a dedicated `SK-TALOS-DISCORD-WEBHOOK-URL` item containing only the complete Discord webhook URL before enabling receivers. The Kubernetes Secret must contain keys `telegram-bot-token`, `telegram-chat-id`, and `discord-webhook-url`; it is deliberately absent from Git.

Bootstrap or refresh the complete Secret with shell tracing disabled and without writing rendered Secret data to disk:

```sh
set +x
export TELEGRAM_BOT_TOKEN="$(bws secret get b2ca02a3-d9b9-4d5b-ba5e-b41c00874fcf -o json | jq -r .value)"
export TELEGRAM_CHAT_ID="$(bws secret get e458b31f-4770-46d9-be92-b41c00880fc9 -o json | jq -r .value)"
export DISCORD_WEBHOOK_URL="$(bws secret get <discord-item-id> -o json | jq -r .value)"
kubectl -n observability create secret generic alertmanager-notifications \
  --from-literal=telegram-bot-token="${TELEGRAM_BOT_TOKEN}" \
  --from-literal=telegram-chat-id="${TELEGRAM_CHAT_ID}" \
  --from-literal=discord-webhook-url="${DISCORD_WEBHOOK_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID DISCORD_WEBHOOK_URL
```

Enable Telegram and Discord receivers only after all three Secret keys exist. The committed grouping and inhibition behavior is designed to remain in place when those receivers are introduced.

## Validation

Render and validate both the alerting component and changed metrics release:

```sh
kubectl kustomize kubernetes/flux/observability/alerting
kubectl kustomize kubernetes/flux/observability/alerting | kubectl apply --server-side --dry-run=server -f -
kubectl kustomize kubernetes/flux/observability/metrics | kubectl apply --server-side --dry-run=server --force-conflicts -f -
```

Live acceptance requires operational scrape resources and VMRule status, all four Flux targets and cert-manager at `up=1`, no permanent scheduler or controller-manager alerts, successful VMAlert evaluations, correct warning/critical inhibition, and no unexpected active local alerts.

Routine rollback suspends or reverts `observability-alerting` and reverts the metrics Helm values. Do not delete Alertmanager's retained PVC when rolling back rules or routing.
