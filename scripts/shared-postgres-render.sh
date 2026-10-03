#!/usr/bin/env bash
# Render only public chart/configuration; PR validation never needs credentials.
set -euo pipefail
scratch_dir=$(mktemp -d)
trap 'rm -rf "$scratch_dir"' EXIT
chart_url=https://github.com/cloudnative-pg/charts/releases/download/cloudnative-pg-v0.29.1/cloudnative-pg-0.29.1.tgz
chart_sha256=b53d3991fe84bcf38767e7702cae78666265427a127a26fff168ab4207d2b1df
curl --fail --silent --show-error --location "$chart_url" -o "$scratch_dir/chart.tgz"
printf '%s  %s\n' "$chart_sha256" "$scratch_dir/chart.tgz" | sha256sum --check --status
# The final values mapping has one source of truth in the HelmRelease.
sed -n '/^  values:/,$p' kubernetes/flux/infrastructure/cloudnative-pg/helm-release.yaml | tail -n +2 | sed 's/^    //' > "$scratch_dir/values.yaml"
helm lint "$scratch_dir/chart.tgz" --values "$scratch_dir/values.yaml" --kube-version 1.36.0
helm template cloudnative-pg "$scratch_dir/chart.tgz" --namespace cnpg-system --values "$scratch_dir/values.yaml" --kube-version 1.36.0 > "$scratch_dir/operator.yaml"
grep -q 'kind: CustomResourceDefinition' "$scratch_dir/operator.yaml"
grep -q 'image:.*1.30.1@sha256:923c267ec29636db3bee20f993d0ec4973fa22998e1adad37da79e4d32b5bc07' "$scratch_dir/operator.yaml"
kubectl kustomize kubernetes/flux/infrastructure/cloudnative-pg >/dev/null
kubectl kustomize kubernetes/flux/infrastructure/shared-postgres-namespace >/dev/null
kubectl kustomize kubernetes/flux/apps/shared-postgres >/dev/null
kubectl kustomize kubernetes/flux/apps/shared-postgres-acl >/dev/null
kubectl kustomize kubernetes/flux/clusters/sk-talos/infrastructure >/dev/null
kubectl kustomize kubernetes/flux/clusters/sk-talos/apps >/dev/null
kubectl kustomize kubernetes/flux/clusters/sk-talos >/dev/null
printf '%s\n' 'Shared PostgreSQL chart and source trees rendered successfully'
