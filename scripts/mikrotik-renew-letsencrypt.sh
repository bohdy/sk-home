#!/usr/bin/env bash

set -euo pipefail

# Resolve the repository root relative to this script so local and CI runs can
# share the same default paths without depending on the current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Keep shared desired-state inventory in a committed file instead of embedding
# device-specific values directly inside workflow YAML or shell logic.
INVENTORY_FILE="${MIKROTIK_CERTIFICATE_INVENTORY:-${REPO_ROOT}/config/mikrotik-letsencrypt-targets.csv}"

# Store ACME state inside the repository workspace so the self-hosted runner can
# reuse prior issuance metadata across workflow runs.
STATE_DIR="${MIKROTIK_ACME_STATE_DIR:-${REPO_ROOT}/.tmp/mikrotik-acme}"
ACME_HOME="${STATE_DIR}/acme-home"
SSH_DIR="${STATE_DIR}/ssh"
KNOWN_HOSTS_FILE="${MIKROTIK_SSH_KNOWN_HOSTS_FILE:-${SSH_DIR}/known_hosts}"
SSH_KEY_FILE="${MIKROTIK_SSH_PRIVATE_KEY_FILE:-${SSH_DIR}/id_ed25519}"
SSH_PORT="${MIKROTIK_SSH_PORT:-22}"
SSH_USERNAME="${MIKROTIK_SSH_USERNAME:?Set MIKROTIK_SSH_USERNAME in the workflow or shell environment.}"
ACME_SERVER="${ACME_SERVER:-letsencrypt}"

# Use Cloudflare API tokens through the variable names that acme.sh expects.
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -z "${CF_Token:-}" ]]; then
  export CF_Token="${CLOUDFLARE_API_TOKEN}"
fi

if [[ -n "${CLOUDFLARE_ZONE_API_TOKEN:-}" && -z "${CF_Zone_Token:-}" ]]; then
  export CF_Zone_Token="${CLOUDFLARE_ZONE_API_TOKEN}"
fi

# Let operators request an immediate reissue during manual workflow_dispatch
# runs while leaving scheduled renewals idempotent by default.
FORCE_RENEWAL="${FORCE_RENEWAL:-false}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

prepare_state_directories() {
  mkdir -p "${ACME_HOME}" "${SSH_DIR}"
  chmod 700 "${STATE_DIR}" "${SSH_DIR}"
}

prepare_ssh_key() {
  if [[ ! -f "${SSH_KEY_FILE}" ]]; then
    echo "Missing SSH private key file: ${SSH_KEY_FILE}" >&2
    exit 1
  fi

  chmod 600 "${SSH_KEY_FILE}"
}

build_ssh_options() {
  printf '%s\n' \
    "-i" "${SSH_KEY_FILE}" \
    "-p" "${SSH_PORT}" \
    "-o" "BatchMode=yes" \
    "-o" "IdentitiesOnly=yes" \
    "-o" "StrictHostKeyChecking=yes" \
    "-o" "UserKnownHostsFile=${KNOWN_HOSTS_FILE}"
}

build_scp_options() {
  printf '%s\n' \
    "-i" "${SSH_KEY_FILE}" \
    "-P" "${SSH_PORT}" \
    "-o" "BatchMode=yes" \
    "-o" "IdentitiesOnly=yes" \
    "-o" "StrictHostKeyChecking=yes" \
    "-o" "UserKnownHostsFile=${KNOWN_HOSTS_FILE}"
}

acme_issue_or_renew() {
  local fqdn="$1"
  local acme_args=(
    --home "${ACME_HOME}"
    --server "${ACME_SERVER}"
    --dns dns_cf
    --issue
    -d "${fqdn}"
    --keylength ec-256
  )

  # Only force reissuance on explicit operator request because unnecessary
  # forced renewals burn through Let's Encrypt rate limits faster.
  if [[ "${FORCE_RENEWAL}" == "true" ]]; then
    acme_args+=(--force)
  fi

  acme.sh "${acme_args[@]}"
}

create_pkcs12_bundle() {
  local fqdn="$1"
  local output_file="$2"
  local output_password="$3"

  # Export a PKCS#12 bundle because RouterOS can import the full certificate and
  # private key in one step from a single uploaded file.
  openssl pkcs12 -export \
    -out "${output_file}" \
    -inkey "${ACME_HOME}/${fqdn}_ecc/${fqdn}.key" \
    -in "${ACME_HOME}/${fqdn}_ecc/fullchain.cer" \
    -password "pass:${output_password}" \
    -name "${fqdn}"
}

create_routeros_import_script() {
  local fqdn="$1"
  local service_name="$2"
  local certificate_name="$3"
  local bundle_basename="$4"
  local bundle_password="$5"
  local script_file="$6"
  local previous_certificate_name
  local script_basename

  previous_certificate_name="${certificate_name}-previous"
  script_basename="$(basename "${script_file}")"

  # Upload a RouterOS script file instead of sending a multi-line command over
  # SSH because RouterOS CLI parsing is fragile when complex scripts are passed
  # as one shell argument from OpenSSH.
  cat > "${script_file}" <<EOF
:local certCn "${fqdn}"
:local serviceName "${service_name}"
:local certName "${certificate_name}"
:local previousCertName "${previous_certificate_name}"
:local bundleFile "${bundle_basename}"
:local bundlePassword "${bundle_password}"
:local importedCertId

:if ([:len [/certificate find where name=\$previousCertName]] > 0) do={
  /certificate remove [find where name=\$previousCertName]
}

:if ([:len [/certificate find where name=\$certName]] > 0) do={
  /certificate set [find where name=\$certName] name=\$previousCertName
}

/certificate import file-name=\$bundleFile passphrase=\$bundlePassword
:delay 2s

:set importedCertId [/certificate find where common-name=\$certCn and private-key=yes]
:if ([:len \$importedCertId] = 0) do={
  :error ("Unable to find imported certificate for common name " . \$certCn)
}

/certificate set \$importedCertId trusted=yes name=\$certName
/ip service set [find where name=\$serviceName] certificate=\$certName disabled=no
/file remove \$bundleFile
/file remove "${script_basename}"
EOF
}

install_routeros_certificate() {
  local fqdn="$1"
  local management_host="$2"
  local service_name="$3"
  local certificate_name="$4"
  local bundle_file="$5"
  local bundle_password="$6"
  local bundle_basename
  local script_file
  local script_basename
  local previous_certificate_name
  local ssh_options=()
  local scp_options=()

  bundle_basename="$(basename "${bundle_file}")"
  script_file="${STATE_DIR}/${fqdn//./-}.rsc"
  script_basename="$(basename "${script_file}")"
  previous_certificate_name="${certificate_name}-previous"

  while IFS= read -r option; do
    ssh_options+=("${option}")
  done < <(build_ssh_options)

  while IFS= read -r option; do
    scp_options+=("${option}")
  done < <(build_scp_options)

  create_routeros_import_script "${fqdn}" "${service_name}" "${certificate_name}" "${bundle_basename}" "${bundle_password}" "${script_file}"

  scp "${scp_options[@]}" "${bundle_file}" "${SSH_USERNAME}@${management_host}:${bundle_basename}"
  scp "${scp_options[@]}" "${script_file}" "${SSH_USERNAME}@${management_host}:${script_basename}"

  ssh "${ssh_options[@]}" "${SSH_USERNAME}@${management_host}" "/import file-name=${script_basename}"

  # Remove the temporary RouterOS script after a successful import so command
  # payloads do not accumulate on the automation runner.
  rm -f "${script_file}"
}

process_inventory_entry() {
  local fqdn="$1"
  local management_host="$2"
  local service_name="$3"
  local certificate_name="$4"
  local safe_name
  local bundle_file
  local bundle_password

  echo "Processing ${fqdn} on ${management_host}"

  acme_issue_or_renew "${fqdn}"

  safe_name="${fqdn//./-}"
  bundle_file="${STATE_DIR}/${safe_name}.p12"
  bundle_password="$(openssl rand -hex 16)"

  create_pkcs12_bundle "${fqdn}" "${bundle_file}" "${bundle_password}"
  install_routeros_certificate "${fqdn}" "${management_host}" "${service_name}" "${certificate_name}" "${bundle_file}" "${bundle_password}"

  # Remove the temporary PKCS#12 bundle after RouterOS import so private key
  # material does not accumulate on the self-hosted runner between jobs.
  rm -f "${bundle_file}"
}

main() {
  local line
  local fqdn
  local management_host
  local service_name
  local certificate_name

  require_command acme.sh
  require_command openssl
  require_command ssh
  require_command scp

  if [[ -z "${CF_Token:-}" ]]; then
    echo "Set CLOUDFLARE_API_TOKEN or CF_Token for the Cloudflare DNS-01 challenge." >&2
    exit 1
  fi

  if [[ ! -f "${KNOWN_HOSTS_FILE}" ]]; then
    echo "Missing known_hosts file: ${KNOWN_HOSTS_FILE}" >&2
    exit 1
  fi

  if [[ ! -f "${INVENTORY_FILE}" ]]; then
    echo "Missing inventory file: ${INVENTORY_FILE}" >&2
    exit 1
  fi

  prepare_state_directories
  prepare_ssh_key

  while IFS= read -r line || [[ -n "${line}" ]]; do
    # Skip comments and blank lines so the inventory remains readable.
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    IFS=',' read -r fqdn management_host service_name certificate_name <<<"${line}"

    if [[ -z "${fqdn}" || -z "${management_host}" ]]; then
      echo "Invalid inventory entry: ${line}" >&2
      exit 1
    fi

    service_name="${service_name:-www-ssl}"
    certificate_name="${certificate_name:-letsencrypt-www-ssl}"

    process_inventory_entry "${fqdn}" "${management_host}" "${service_name}" "${certificate_name}"
  done < "${INVENTORY_FILE}"
}

main "$@"
