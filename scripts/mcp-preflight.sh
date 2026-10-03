#!/usr/bin/env bash
# Validate the staged MCP boundary without contacting the cluster, NAS,
# Grafana, OpenAI, Bitwarden, or any production runner.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_bin="${KUBECTL_BIN:-kubectl}"

# Live checks are opt-in and only inspect readiness, public TLS and Secret key
# names. Backend permissions and client association require separate evidence.
if [[ "${1:---static}" == "--live" ]]; then
  component="${2:-}"
  case "${component}" in grafana|synology) ;; *) echo "Use --live grafana|synology" >&2; exit 2 ;; esac
  "${kubectl_bin}" wait nodes --all --for=condition=Ready --timeout=30s >/dev/null
  for name in cilium dns; do
    "${kubectl_bin}" -n flux-system wait kustomization "${name}" --for=condition=Ready --timeout=30s >/dev/null
  done
  namespace="mcp-${component}"
  secret_keys="$("${kubectl_bin}" -n "${namespace}" get secret "${namespace}-credentials" -o go-template='{{range $key,$value := .data}}{{printf "%s\n" $key}}{{end}}')"
  required_keys=(control-plane-api-key)
  if [[ "${component}" == grafana ]]; then
    required_keys+=(grafana-service-account-token)
    "${kubectl_bin}" -n flux-system wait kustomization observability-metrics --for=condition=Ready --timeout=30s >/dev/null
    curl --fail --silent --show-error --max-time 10 --output /dev/null https://grafana.bohdal.name/api/health
  else
    required_keys+=(synology-username synology-password)
    curl --fail --silent --show-error --max-time 10 --output /dev/null https://nas.bohdal.name:5001/
  fi
  for key in "${required_keys[@]}"; do
    if ! printf '%s\n' "${secret_keys}" | grep -Fxq "${key}"; then
      echo "Required credential key metadata is missing" >&2; exit 1
    fi
  done
  image="$("${kubectl_bin}" -n "${namespace}" get deployment "${namespace}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [[ "${image}" =~ @sha256:[a-f0-9]{64}$ ]] || { echo "A reviewed immutable image is required" >&2; exit 1; }
  tunnel_id="$("${kubectl_bin}" -n "${namespace}" get configmap "${namespace}-config" -o jsonpath='{.data.control-plane-tunnel-id}')"
  [[ -n "${tunnel_id}" && "${tunnel_id}" != activation-required ]] || { echo "Tunnel identity is not configured" >&2; exit 1; }
  echo "Infrastructure metadata passed. Backend effective permissions, root/link behavior, fresh network inventory and both client bindings remain unverified; this is not activation approval." >&2
  exit 3
elif [[ "${1:---static}" != "--static" ]]; then
  echo "Use --static or --live grafana|synology" >&2; exit 2
fi

for component in mcp-grafana mcp-synology; do
  "${kubectl_bin}" kustomize "${repo_root}/kubernetes/flux/apps/${component}" >/dev/null
done
"${kubectl_bin}" kustomize "${repo_root}/kubernetes/flux/clusters/sk-talos/apps" >/dev/null

# The parent tree must list both independently suspended children.
for child in mcp-grafana mcp-synology; do
  grep -q "name: ${child}" "${repo_root}/kubernetes/flux/clusters/sk-talos/apps/${child}-kustomization.yaml"
  if ! grep -q "suspend: true" "${repo_root}/kubernetes/flux/clusters/sk-talos/apps/${child}-kustomization.yaml"; then
    deployment="${repo_root}/kubernetes/flux/apps/${child}/deployment.yaml"
    if ! grep -q 'replicas: 0' "${deployment}"; then
      grep -Eq 'image: [^ ]+@sha256:[a-f0-9]{64}$' "${deployment}" || { echo "Active MCP workload requires an immutable digest" >&2; exit 1; }
      if grep -q 'control-plane-tunnel-id: activation-required' "${repo_root}/kubernetes/flux/apps/${child}/configmap.yaml"; then
        echo "Active MCP workload requires a tunnel identity" >&2; exit 1
      fi
    fi
  fi
done

# Staged image references and tunnel IDs deliberately cannot activate a live
# workload. A digest is added only by the reviewed trusted image workflow.
: # Placeholder references are permitted only behind suspension or zero replicas.

# No network-facing Service, ingress, PVC, or committed Secret is part of this
# tunnel-only integration.
if grep -R -n -E '^kind: (Service|Ingress|PersistentVolumeClaim|Secret)$' "${repo_root}/kubernetes/flux/apps/mcp-grafana" "${repo_root}/kubernetes/flux/apps/mcp-synology"; then
  echo "MCP components must not expose a Service, ingress, PVC, or Secret" >&2
  exit 1
fi

# Keep credentials out of the non-secret tunnel configuration and manifests.
# The two exact env references are the reviewed tunnel contract; they name a
# Secret-backed variable and contain no credential material. Every other
# key/token/password value remains a static literal violation.
if grep -R -n -E '(^|[[:space:]])(password|passwd|token|api_key):[[:space:]]*[^[:space:]]|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
  "${repo_root}/kubernetes/flux/apps/mcp-grafana" "${repo_root}/kubernetes/flux/apps/mcp-synology" \
  | grep -v -E 'api_key:[[:space:]]+env:CONTROL_PLANE_API_KEY[[:space:]]*$'; then
  echo "MCP staged manifests contain an unsupported credential reference" >&2
  exit 1
fi

echo "MCP staged manifests passed credential-free preflight."
