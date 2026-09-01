#!/usr/bin/env bash
set -euo pipefail

# This preflight is deliberately read-only. It verifies live prerequisites
# before the printer is pointed at the relay and never reads Secret data.
smtp_vip="${SMTP_RELAY_VIP:-10.1.30.58}"
printer_ip="${SMTP_RELAY_PRINTER_IP:-10.1.10.250}"
smtp_hostname="${SMTP_RELAY_HOSTNAME:-smtp.internal.bohdal.name}"
printer_hostname="${SMTP_RELAY_PRINTER_HOSTNAME:-printer.sk.bohdal.name}"
cluster_issuer="${SMTP_RELAY_CLUSTER_ISSUER:-letsencrypt-production}"
internal_dns_server="${SMTP_RELAY_INTERNAL_DNS_SERVER:-10.1.30.53}"
public_dns_server="${SMTP_RELAY_PUBLIC_DNS_SERVER:-1.1.1.1}"

fail() {
  printf 'smtp relay preflight: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

require_command kubectl
require_command jq
require_command dig

# Verify that the requested VIP belongs to the declared Cilium pool and is not
# already assigned or requested by another live Service. Once Flux has created
# the relay Service, that one expected assignment is checked separately below.
pool_json="$(kubectl get ciliumloadbalancerippools -A -o json)" || fail 'cannot read Cilium LoadBalancer pools'
jq -e --arg pool_cidr '10.1.30.0/24' \
  '[.items[]?.spec.blocks[]?.cidr] | any(. == $pool_cidr)' <<<"${pool_json}" >/dev/null \
  || fail 'Cilium pool 10.1.30.0/24 is not present'

services_json="$(kubectl get services -A -o json)" || fail 'cannot read live Services'
jq -e --arg vip "${smtp_vip}" \
  '[.items[]? | select(.metadata.namespace != "smtp-relay" or .metadata.name != "smtp-relay") | .status.loadBalancer.ingress[]?.ip, .spec.loadBalancerIP, .metadata.annotations["lbipam.cilium.io/ips"]] | any(. == $vip)' \
  <<<"${services_json}" >/dev/null \
  && fail "VIP ${smtp_vip} is already assigned to a live Service"

# The existing StorageClass must retain the queue and wait for a scheduled Pod
# before provisioning its single-writer Synology volume.
storage_json="$(kubectl get storageclass synology-iscsi-retain -o json)" || fail 'retained Synology StorageClass is unavailable'
jq -e '
  .provisioner == "csi.san.synology.com" and
  .reclaimPolicy == "Retain" and
  .volumeBindingMode == "WaitForFirstConsumer" and
  .allowVolumeExpansion == true
' <<<"${storage_json}" >/dev/null || fail 'retained Synology StorageClass does not match the relay contract'

# cert-manager must already have a registered production issuer before the
# relay Certificate is reconciled.
issuer_json="$(kubectl get clusterissuer "${cluster_issuer}" -o json)" || fail "ClusterIssuer ${cluster_issuer} is unavailable"
jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' <<<"${issuer_json}" >/dev/null \
  || fail "ClusterIssuer ${cluster_issuer} is not Ready"

# Split DNS and public DMARC are checked independently: the former protects
# printer certificate validation, while the latter protects Seznam alignment.
require_exact_a_record() {
  local hostname="$1"
  local expected_ip="$2"
  local answers="$3"
  local normalized_answers

  # An extra public or stale A record could send the printer to the wrong
  # endpoint, so accepting one matching answer is not sufficient here.
  normalized_answers="$(printf '%s\n' "${answers}" | sed '/^[[:space:]]*$/d' | sort -u)"
  [[ "${normalized_answers}" == "${expected_ip}" ]] || fail "${hostname} does not resolve exclusively to ${expected_ip}"
}

smtp_dns="$(dig +short @"${internal_dns_server}" "${smtp_hostname}" A)"
require_exact_a_record "${smtp_hostname}" "${smtp_vip}" "${smtp_dns}"
printer_dns="$(dig +short @"${internal_dns_server}" "${printer_hostname}" A)"
require_exact_a_record "${printer_hostname}" "${printer_ip}" "${printer_dns}"
dmarc_txt="$(dig +short @"${public_dns_server}" _dmarc.sk.bohdal.net TXT)"
# Match complete DMARC tags so a child policy such as `sp=none` cannot satisfy
# the required organizational policy. DNS tools wrap TXT records in quotes;
# remove those transport markers before checking the semicolon-delimited tags.
dmarc_record="$(printf '%s\n' "${dmarc_txt}" | tr -d '"')"
printf '%s\n' "${dmarc_record}" | grep -Eiq '(^|[;[:space:]])v[[:space:]]*=[[:space:]]*DMARC1([;[:space:]]|$)' \
  || fail 'DMARC TXT record is missing'
printf '%s\n' "${dmarc_record}" | grep -Eiq '(^|[;[:space:]])p[[:space:]]*=[[:space:]]*none([;[:space:]]|$)' \
  || fail 'DMARC policy is not p=none'

# Require the Flux child Kustomization to report Ready so the checks below
# describe the repository-managed workload rather than an incomplete manual
# apply or a stale object from a previous rollout.
flux_json="$(kubectl get kustomization.kustomize.toolkit.fluxcd.io smtp-relay -n flux-system -o json)" || fail 'relay Flux Kustomization is missing'
jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' <<<"${flux_json}" >/dev/null \
  || fail 'relay Flux Kustomization is not Ready'

# These checks inspect only resource status and metadata. Secret values are
# never passed to jq, printed, or included in diagnostics.
deployment_json="$(kubectl get deployment smtp-relay -n smtp-relay -o json)" || fail 'relay Deployment is missing'
jq -e '
  .spec.replicas == 1 and
  .status.availableReplicas == 1 and
  .spec.template.spec.serviceAccountName == "smtp-relay" and
  .spec.template.spec.automountServiceAccountToken == false and
  .spec.template.metadata.labels["vector.dev/exclude"] == "true" and
  .spec.template.metadata.annotations["vector.dev/exclude"] == "true" and
  .spec.template.metadata.annotations["velero.io/exclude-from-backup"] == "true" and
  ([.spec.template.spec.containers[]?] | length == 2) and
  ([.spec.template.spec.containers[]?.securityContext.readOnlyRootFilesystem] | all)
' <<<"${deployment_json}" >/dev/null \
  || fail 'relay Deployment does not have one available replica'

service_json="$(kubectl get service smtp-relay -n smtp-relay -o json)" || fail 'relay Service is missing'
jq -e --arg vip "${smtp_vip}" --arg printer_ip "${printer_ip}" '
  .spec.type == "LoadBalancer" and
  ([.spec.ports[]?] | length == 1) and
  ([.spec.ports[]? | select(.port == 587 and .protocol == "TCP")] | length == 1) and
  ([.spec.loadBalancerSourceRanges[]?] | any(. == ($printer_ip + "/32"))) and
  ([.status.loadBalancer.ingress[]?.ip] | any(. == $vip))
' <<<"${service_json}" >/dev/null || fail 'relay Service does not match the private 587 boundary'

kubectl get secret smtp-relay-upstream -n smtp-relay -o name >/dev/null \
  || fail 'smtp-relay-upstream Secret is missing'
certificate_json="$(kubectl get certificate smtp-relay -n smtp-relay -o json)" || fail 'relay Certificate is missing'
jq -e --arg smtp_hostname "${smtp_hostname}" '
  ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0) and
  .spec.secretName == "smtp-relay-tls" and
  .spec.dnsNames == [$smtp_hostname]
' <<<"${certificate_json}" >/dev/null \
  || fail 'relay Certificate is not Ready'

pvc_json="$(kubectl get pvc smtp-relay-queue -n smtp-relay -o json)" || fail 'relay queue PVC is missing'
jq -e '
  .status.phase == "Bound" and
  .spec.accessModes == ["ReadWriteOnce"] and
  .spec.storageClassName == "synology-iscsi-retain" and
  .spec.resources.requests.storage == "1Gi"
' <<<"${pvc_json}" >/dev/null || fail 'relay queue PVC does not match the durable queue contract'

if kubectl api-resources --api-group=snapshot.storage.k8s.io --no-headers 2>/dev/null \
  | awk '$1 == "volumesnapshots" { found = 1 } END { exit !found }'; then
  snapshots_json="$(kubectl get volumesnapshots.snapshot.storage.k8s.io -A -o json)" || fail 'cannot inspect VolumeSnapshots'
  jq -e --arg claim 'smtp-relay-queue' \
    '[.items[]?.spec.source.persistentVolumeClaimName] | any(. == $claim)' <<<"${snapshots_json}" >/dev/null \
    && fail 'a VolumeSnapshot selects smtp-relay-queue'
fi

printf '%s\n' 'smtp relay preflight: passed read-only prerequisite checks'
