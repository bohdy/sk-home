#!/bin/sh
# RouterOS represents a dynamic-to-static DHCP conversion as a menu command,
# not a lease property. The Terraform provider lacks that command, so this
# one-shot helper performs only the missing operation through the same HTTPS
# endpoint and credentials that the provider uses.
set -eu

: "${MIKROTIK_API_BASE_URL:?MIKROTIK_API_BASE_URL must be set}"
: "${MIKROTIK_LEASE_ID:?MIKROTIK_LEASE_ID must be set}"
: "${MIKROTIK_PASSWORD:?MIKROTIK_PASSWORD must be set}"
: "${MIKROTIK_USERNAME:?MIKROTIK_USERNAME must be set}"

# The provider defaults to accepting the gateway's current self-signed TLS
# certificate. Match that explicit bootstrap policy rather than broadening the
# trust boundary or putting certificate material in this helper.
api_base_url="${MIKROTIK_API_BASE_URL%/}/rest"
lease_url="${api_base_url}/ip/dhcp-server/lease/${MIKROTIK_LEASE_ID}"

# A failed apply can leave the RouterOS command complete before Terraform saves
# state. Read first so the next apply becomes a safe no-op in that situation.
lease_json="$(curl --fail --silent --show-error --insecure --user "${MIKROTIK_USERNAME}:${MIKROTIK_PASSWORD}" "${lease_url}")"
if printf '%s' "${lease_json}" | jq -e '.dynamic == "false" or .dynamic == false' >/dev/null; then
  exit 0
fi

# POST maps to RouterOS console commands. `numbers` selects only this imported
# lease ID; no command can affect any other DHCP record.
curl --fail --silent --show-error --insecure --user "${MIKROTIK_USERNAME}:${MIKROTIK_PASSWORD}" \
  --request POST \
  --header 'content-type: application/json' \
  --data "{\"numbers\":\"${MIKROTIK_LEASE_ID}\"}" \
  "${api_base_url}/ip/dhcp-server/lease/make-static" >/dev/null

# Fail closed unless RouterOS confirms the command produced a static lease.
lease_json="$(curl --fail --silent --show-error --insecure --user "${MIKROTIK_USERNAME}:${MIKROTIK_PASSWORD}" "${lease_url}")"
printf '%s' "${lease_json}" | jq -e '.dynamic == "false" or .dynamic == false' >/dev/null
