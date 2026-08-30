# UniFi Poller

This component defines the digest-pinned UniFi Poller v5.1.0 as one stateless, ClusterIP-only replica in the `observability` namespace. It reads controller, site, topology, and client data from the private `unifi-console.unifi.svc.cluster.local:8443` endpoint and serves the cached result to VMAgent on port `9130`.

The declarative configuration is prepared in this branch; live reconciliation and authentication acceptance remain pending until the dedicated read-only credential and Bitwarden-backed Kubernetes Secret exist and the post-reconcile checks below pass.

The controller's native console listener uses a self-signed certificate, so `UP_UNIFI_DEFAULT_VERIFY_SSL=false` is restricted to this in-cluster endpoint. The Cilium policy still permits the poller to reach only the controller console and CoreDNS; it has no device, database, or Internet egress.

## Secret prerequisite

Before reconciling this component, create a dedicated local UniFi Network user scoped to this private controller endpoint. Grant only the UniFi Network read-only/viewer role and the inventories needed by the poller; do not grant administrator, device-configuration, account-management, or access to other UniFi applications. Do not reuse the administrator identity used for controller administration or AP SNMP configuration.

Create two dedicated Bitwarden Secrets Manager items, each containing exactly one value:

- `SK-TALOS-UNIFI-POLLER-USERNAME`: the local UniFi Network username only, without a key name, JSON, or surrounding whitespace.
- `SK-TALOS-UNIFI-POLLER-PASSWORD`: the corresponding password only, without a key name, JSON, or line breaks.

The item IDs are intentionally placeholders below because they have not been verified. Replace each placeholder only after its named item exists and BWS access has been validated; never invent or reuse an ID. The Kubernetes Secret is deliberately absent from Git.

## Secret bootstrap

Fetch both values into memory and create `unifi-poller-auth` without printing values, enabling shell tracing, or writing a rendered Secret to disk. The script fails before applying anything if either item ID is still a placeholder, BWS returns an error, or either item is empty or contains a line break.

```bash
set -euo pipefail
set +x

cleanup() {
  unset UNIFI_POLLER_USERNAME UNIFI_POLLER_PASSWORD \
    UNIFI_POLLER_USERNAME_B64 UNIFI_POLLER_PASSWORD_B64
}
trap cleanup EXIT

UNIFI_POLLER_USERNAME_ITEM_ID='REPLACE_WITH_USERNAME_ITEM_ID'
UNIFI_POLLER_PASSWORD_ITEM_ID='REPLACE_WITH_PASSWORD_ITEM_ID'

if [ -z "${UNIFI_POLLER_USERNAME_ITEM_ID}" ] || [ "${UNIFI_POLLER_USERNAME_ITEM_ID}" = 'REPLACE_WITH_USERNAME_ITEM_ID' ] || \
  [ -z "${UNIFI_POLLER_PASSWORD_ITEM_ID}" ] || [ "${UNIFI_POLLER_PASSWORD_ITEM_ID}" = 'REPLACE_WITH_PASSWORD_ITEM_ID' ]; then
  echo 'Replace the UniFi Poller Bitwarden item IDs after both items exist.' >&2
  exit 1
fi

get_bw_value() {
  bws secret get "$1" -o json |
    jq -er '.value | strings | select(length > 0) | select(contains("\n") | not) | select(contains("\r") | not)'
}

UNIFI_POLLER_USERNAME="$(get_bw_value "${UNIFI_POLLER_USERNAME_ITEM_ID}")"
UNIFI_POLLER_PASSWORD="$(get_bw_value "${UNIFI_POLLER_PASSWORD_ITEM_ID}")"

# Encode from stdin so neither plaintext nor base64 credentials enter an
# external-process argument; the generated manifest is passed to kubectl only
# through stdin and is never written to disk.
UNIFI_POLLER_USERNAME_B64="$(printf '%s' "${UNIFI_POLLER_USERNAME}" | base64 | tr -d '\r\n')"
UNIFI_POLLER_PASSWORD_B64="$(printf '%s' "${UNIFI_POLLER_PASSWORD}" | base64 | tr -d '\r\n')"

kubectl -n observability apply --server-side --field-manager=unifi-poller-bootstrap -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: unifi-poller-auth
  namespace: observability
type: Opaque
data:
  username: ${UNIFI_POLLER_USERNAME_B64}
  password: ${UNIFI_POLLER_PASSWORD_B64}
EOF
```

If BWS authentication or either lookup fails, fix access or the item contract and rerun the complete procedure; do not substitute a plaintext value or create a partial Secret. Keep the shell tracing-disabled session short and unset any copied values immediately after the command completes.

## Rotation

Update both dedicated Bitwarden items first, rerun the complete bootstrap procedure, and restart the Deployment because Secret-backed environment variables are read only when a new pod starts:

```bash
kubectl -n observability rollout restart deployment/unifi-poller
kubectl -n observability rollout status deployment/unifi-poller --timeout=120s
```

Do not remove the old controller credential until the new pod is Ready and the post-reconcile checks below pass. If rotation fails, restore the last known-good Bitwarden values, rerun bootstrap, and restart again without placing either value in shell history, manifests, or logs.

## Validation

Render and validate only this component before reconciliation:

```bash
kubectl kustomize kubernetes/flux/observability/unifi-poller >/dev/null
kubectl kustomize kubernetes/flux/observability/unifi-poller |
  kubectl apply --server-side --dry-run=server -f - >/dev/null
```

After Flux reconciliation, require the Secret to contain exactly `username` and `password`, a Ready pod with no repeated restarts, and `unpoller_controller_up` equal to `1`. The latter proves that the poller authenticated to and successfully refreshed from the controller rather than merely serving an empty HTTP endpoint. Check the metric without printing the response:

```bash
set -euo pipefail
set +x
kubectl -n observability get secret unifi-poller-auth -o json |
  jq -e '(.data | keys | sort) == ["password", "username"]' >/dev/null
kubectl -n observability rollout status deployment/unifi-poller --timeout=120s

kubectl -n observability port-forward service/unifi-poller 19130:9130 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "${PORT_FORWARD_PID}" 2>/dev/null || true' EXIT
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if curl --fail --silent --show-error http://127.0.0.1:19130/metrics 2>/dev/null |
    rg -q '^unpoller_controller_up\{[^}]*\} 1$'; then
    exit 0
  fi
  sleep 1
done
echo 'UniFi Poller controller metric did not report a successful refresh.' >&2
exit 1
```

Review the last 200 container log lines only through a redaction-safe terminal and reject any authentication errors, repeated controller request failures, or credential values. The following check keeps both the bounded log sample and Secret values in memory and emits only a generic failure message:

```bash
set -euo pipefail
set +x
POD_NAME="$(kubectl -n observability get pod -l app.kubernetes.io/name=unifi-poller -o jsonpath='{.items[0].metadata.name}')"
POLLER_LOGS="$(kubectl -n observability logs "${POD_NAME}" -c unifi-poller --tail=200 2>/dev/null)"
POLLER_USERNAME="$(kubectl -n observability get secret unifi-poller-auth -o json | jq -er '.data.username | @base64d')"
POLLER_PASSWORD="$(kubectl -n observability get secret unifi-poller-auth -o json | jq -er '.data.password | @base64d')"

if [ -z "${POLLER_USERNAME}" ] || [ -z "${POLLER_PASSWORD}" ] ||
  printf '%s' "${POLLER_LOGS}" | rg -qi 'unauthori[sz]ed|authentication failed|invalid credentials|login failed|request failed' >/dev/null ||
  case "${POLLER_LOGS}" in *"${POLLER_USERNAME}"*|*"${POLLER_PASSWORD}"*) true;; *) false;; esac; then
  echo 'UniFi Poller authentication/request failure or credential exposure found in logs.' >&2
  exit 1
fi
```

Do not paste raw logs, Secret data, rendered Secret YAML, or metric output containing unexpected labels into tickets or CI output. The Deployment must keep credential values in Secret-backed environment variables only; verify that rendered manifests, pod arguments, logs, and metrics contain no credential values.

## Rollback

Routine rollback suspends or reverts the `observability-unifi-poller` Flux Kustomization to the last reviewed revision. The external Secret may remain for redeployment, but delete it explicitly only when UniFi Poller monitoring is permanently abandoned and the dedicated controller user has also been disabled.
