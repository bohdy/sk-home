# Flow GeoIP

This component refreshes a local MaxMind GeoLite2 City CSV database and imports it into ClickHouse tables consumed by the `flows.ip_geo` IP_TRIE dictionary. Raw flow records remain unchanged; the `sk-flow` dashboard performs query-time enrichment so historical rows use the current lookup data.

The map policy enables city markers for countries at or above 500,000 km2 and falls back to Grafana country markers for smaller countries, missing city records, and records whose GeoLite2 accuracy radius exceeds 100 km. The accuracy limit is committed in `flows.geo_settings`; the large-country policy is committed in `flows.geo_country_policy`, so either can be reviewed without changing flow ingestion.

## Secret Bootstrap

Create two Bitwarden Secrets Manager items, each containing one value:

- `SK-TALOS-MAXMIND-GEOLITE2-ACCOUNT-ID`: the MaxMind Account ID
- `SK-TALOS-MAXMIND-GEOLITE2-LICENSE-KEY`: the MaxMind license key authorized to download GeoLite2 City

Then create the Kubernetes Secret `maxmind-geoip` in the `observability` namespace from those items. It must contain only `account-id` and `license-key`; do not commit either value or place it in a command log. Replace the placeholder item IDs below with the IDs returned by BWS after creating the items.

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability create secret generic maxmind-geoip \
  --from-file=account-id=<(bws secret get <account-id-item-id> -o json | jq -r .value) \
  --from-file=license-key=<(bws secret get <license-key-item-id> -o json | jq -r .value) \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
```

Keep shell tracing disabled while the values are present. The bootstrap Job runs once after the ClickHouse dictionary exists; the CronJob refreshes the database twice weekly. The Flux Kustomization is intentionally non-blocking when the Secret has not yet been created, so the collector and dashboard can reconcile independently.

The updater uses HTTPS with certificate validation, follows MaxMind's documented R2 redirect, retries transient download failures within a bounded window, imports CSV files with bounded serial ClickHouse parsing, allows egress only to the two required MaxMind names, and never sends individual flow addresses to MaxMind. The downloaded CSV files are staged in ephemeral storage and are not retained outside ClickHouse.

The deployment must retain MaxMind's required GeoLite2 attribution and comply with the account's current license terms; the repository stores neither the database nor the license credential.

## Validation

```bash
kubectl kustomize kubernetes/flux/observability/flow-geoip
kubectl kustomize kubernetes/flux/observability/flow-geoip | kubectl apply --server-side --dry-run=server -f -
```

After the Secret is available, require the bootstrap Job to complete, `system.dictionaries` to show `flows.ip_geo` as loaded, and representative dictionary lookups to return country, city, latitude, longitude, and accuracy-radius values without exposing the MaxMind credential in logs.
