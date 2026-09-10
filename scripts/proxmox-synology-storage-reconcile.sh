#!/usr/bin/env bash
set -euo pipefail

# Reconcile the small part of Proxmox/Synology storage that the repository's
# pinned providers cannot represent. The script is intentionally workflow-only:
# pull-request validation never supplies these credentials or invokes it.

usage() {
  cat >&2 <<'EOF'
Usage: proxmox-synology-storage-reconcile.sh <check|apply> <desired-json>

check performs read-only identity and drift checks. apply may update only the
declared Proxmox storage entries, the Synology target session limit, and missing
Synology initiators. Both modes require the endpoint and credential variables.
EOF
}

fail() {
  echo "storage reconciliation failed: $*" >&2
  exit 1
}

mode="${1:-}"
desired_file="${2:-${STORAGE_DESIRED_FILE:-}}"
[[ "$mode" == "check" || "$mode" == "apply" ]] || {
  usage
  exit 2
}
[[ -n "$desired_file" ]] || {
  usage
  exit 2
}

for command_name in curl jq python3 mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command is unavailable: $command_name"
done

for variable_name in PROXMOX_ENDPOINT PROXMOX_API_TOKEN SYNOLOGY_ENDPOINT SYNOLOGY_USERNAME SYNOLOGY_PASSWORD; do
  [[ -n "${!variable_name:-}" ]] || fail "required environment variable is missing: $variable_name"
done

[[ -f "$desired_file" ]] || fail "desired-state file does not exist"

desired_json="$(<"$desired_file")"
jq -e '
  (.proxmox.api_node | type == "string")
  and (.proxmox.cluster_name | type == "string")
  and (.proxmox.nodes | type == "array" and length == 2 and all(.[]; type == "string"))
  and (.proxmox.storages.iscsi | type == "object")
  and (.proxmox.storages.lvm | type == "object")
  and (.proxmox.storages.local_lvm | type == "object")
  and (.synology.endpoint | type == "string")
  and (.synology.target_id | type == "string")
  and (.synology.target_iqn | type == "string")
  and (.synology.host_id | type == "string")
  and (.synology.lun_uuid | type == "string")
  and (.synology.initiator_iqns | type == "array" and length == 2 and all(.[]; type == "string"))
' <<<"$desired_json" >/dev/null || fail "desired-state JSON has an invalid shape"

tmpdir="$(mktemp -d)"
cookie_file="$tmpdir/synology.cookies"
chmod 600 "$cookie_file"

cleanup() {
  # Logout is best effort and never emits the response because session data is
  # infrastructure-sensitive even though it is not a long-lived credential.
  if [[ -n "${SYNOLOGY_SID:-}" && -n "${SYNOLOGY_TOKEN:-}" ]]; then
    synology_call "SYNO.API.Auth" "logout" 3 '{}' >/dev/null 2>&1 || true
  fi
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

proxmox_endpoint="${PROXMOX_ENDPOINT%/}"
case "$proxmox_endpoint" in
  https://*/api2/json) ;;
  https://*) proxmox_endpoint="${proxmox_endpoint}/api2/json" ;;
  *) fail "PROXMOX_ENDPOINT must use HTTPS" ;;
esac

synology_endpoint="${SYNOLOGY_ENDPOINT%/}"
[[ "$(jq -r '.synology.endpoint' <<<"$desired_json")" == "$synology_endpoint" ]] || fail "SYNOLOGY_ENDPOINT does not match the declared endpoint"
synology_api_url="${synology_endpoint}/webapi/entry.cgi"

urlencode_pairs() {
  # Encode form fields in Python so values never need to be interpolated into
  # shell-evaluated curl arguments. Callers must not pass secrets as arguments.
  python3 - "$@" <<'PY'
import sys
import urllib.parse

pairs = {}
for item in sys.argv[1:]:
    key, separator, value = item.partition("=")
    if not separator:
        raise SystemExit("malformed form pair")
    pairs[key] = value
print(urllib.parse.urlencode(pairs))
PY
}

proxmox_request() {
  local method="$1"
  local url="$2"
  local body="${3:-}"

  # Use curl's stdin configuration so the Proxmox token is never present in a
  # process argument or a logged command line.
  REQUEST_BODY="$body" REQUEST_METHOD="$method" REQUEST_URL="$url" \
    jq -nr '
      "url = " + ($ENV.REQUEST_URL | @json),
      "request = " + ($ENV.REQUEST_METHOD | @json),
      "fail",
      "silent",
      "show-error",
      "connect-timeout = 10",
      "max-time = 60",
      "header = " + (("Authorization: PVEAPIToken=" + $ENV.PROXMOX_API_TOKEN) | @json),
      (if ($ENV.REQUEST_BODY // "") == "" then empty else "data = " + ($ENV.REQUEST_BODY | @json) end)
    ' | curl --config -
}

proxmox_response_ok() {
  # Proxmox returns a data member for successful API calls and an errors member
  # for failed calls. Do not print the response if this guard fails.
  jq -e '((has("errors") | not) and (has("data") or .success == true))' >/dev/null <<<"$1"
}

proxmox_storage_list=""
refresh_proxmox_storage() {
  proxmox_storage_list="$(proxmox_request GET "${proxmox_endpoint}/cluster/storage")" || fail "Proxmox storage inventory request failed"
  jq -e '.data | type == "array"' >/dev/null <<<"$proxmox_storage_list" || fail "Proxmox returned an invalid storage inventory"
}

proxmox_storage_entry() {
  local storage_id="$1"
  jq -ce --arg storage_id "$storage_id" '[.data[] | select((.storage // .id) == $storage_id)] | if length == 1 then .[0] else empty end' <<<"$proxmox_storage_list"
}

storage_content_csv() {
  jq -r '(.content // []) | if type == "array" then sort | join(",") else tostring end' <<<"$1"
}

storage_nodes_csv() {
  jq -r 'if .nodes == null then "" elif (.nodes | type) == "array" then (.nodes | sort | join(",")) else (.nodes | tostring) end' <<<"$1"
}

storage_nodes_delete_pair() {
  # Proxmox treats an omitted update field as unchanged. A null desired nodes
  # value instead means the node restriction must be removed explicitly.
  if jq -e '.nodes == null' >/dev/null <<<"$1"; then
    printf '%s\n' 'delete=nodes'
  fi
}

storage_identity_matches() {
  local live="$1"
  local expected="$2"
  local kind="$3"

  case "$kind" in
    iscsi)
      jq -e --argjson expected "$expected" '
        .type == $expected.type
        and .portal == $expected.portal
        and .target == $expected.target
      ' >/dev/null <<<"$live"
      ;;
    lvm)
      jq -e --argjson expected "$expected" '
        .type == $expected.type
        and (.vgname // .volume_group) == $expected.volume_group
        and .base == $expected.base
      ' >/dev/null <<<"$live"
      ;;
    local_lvm)
      jq -e --argjson expected "$expected" '
        .type == $expected.type
        and (.vgname // .volume_group) == $expected.volume_group
        and (.thinpool // .thin_pool) == $expected.thin_pool
      ' >/dev/null <<<"$live"
      ;;
    *)
      fail "unknown Proxmox storage kind: $kind"
      ;;
  esac
}

storage_contract_matches() {
  local live="$1"
  local expected="$2"
  local kind="$3"

  case "$kind" in
    iscsi)
      jq -e --argjson expected "$expected" '
        def list($value):
          if $value == null then []
          elif ($value | type) == "array" then $value | sort
          elif ($value | type) == "string" then ($value | split(",") | map(select(length > 0)) | sort)
          else [] end;
        (.type == $expected.type)
        and (.portal == $expected.portal)
        and (.target == $expected.target)
        and (list(.content) == list($expected.content))
        and (list(.nodes) == list($expected.nodes))
      ' >/dev/null <<<"$live"
      ;;
    lvm)
      jq -e --argjson expected "$expected" '
        def list($value):
          if $value == null then []
          elif ($value | type) == "array" then $value | sort
          elif ($value | type) == "string" then ($value | split(",") | map(select(length > 0)) | sort)
          else [] end;
        def truthy($value): ($value == true or $value == 1 or $value == "1");
        (.type == $expected.type)
        and ((.vgname // .volume_group) == $expected.volume_group)
        and (.base == $expected.base)
        and (list(.content) == list($expected.content))
        and (truthy(.shared) == $expected.shared)
        and ((.saferemove // 0 | tostring) == ($expected.saferemove | tostring))
        and (list(.nodes) == list($expected.nodes))
      ' >/dev/null <<<"$live"
      ;;
    local_lvm)
      jq -e --argjson expected "$expected" '
        def list($value):
          if $value == null then []
          elif ($value | type) == "array" then $value | sort
          elif ($value | type) == "string" then ($value | split(",") | map(select(length > 0)) | sort)
          else [] end;
        (.type == $expected.type)
        and ((.vgname // .volume_group) == $expected.volume_group)
        and ((.thinpool // .thin_pool) == $expected.thin_pool)
        and (list(.content) == list($expected.content))
        and (list(.nodes) == list($expected.nodes))
      ' >/dev/null <<<"$live"
      ;;
    *)
      fail "unknown Proxmox storage kind: $kind"
      ;;
  esac
}

proxmox_create_body() {
  local expected="$1"
  local kind="$2"
  local storage_id type content nodes

  storage_id="$(jq -er '.id' <<<"$expected")"
  type="$(jq -er '.type' <<<"$expected")"
  content="$(storage_content_csv "$expected")"
  nodes="$(storage_nodes_csv "$expected")"

  case "$kind" in
    iscsi)
      urlencode_pairs \
        "storage=${storage_id}" "type=${type}" \
        "portal=$(jq -er '.portal' <<<"$expected")" \
        "target=$(jq -er '.target' <<<"$expected")" "content=${content}"
      ;;
    lvm)
      if [[ -n "$nodes" ]]; then
        urlencode_pairs \
          "storage=${storage_id}" "type=${type}" \
          "vgname=$(jq -er '.volume_group' <<<"$expected")" \
          "base=$(jq -er '.base' <<<"$expected")" "content=${content}" \
          "saferemove=$(jq -er '.saferemove' <<<"$expected")" \
          "shared=$(jq -er 'if .shared then 1 else 0 end' <<<"$expected")" \
          "nodes=${nodes}"
      else
        urlencode_pairs \
          "storage=${storage_id}" "type=${type}" \
          "vgname=$(jq -er '.volume_group' <<<"$expected")" \
          "base=$(jq -er '.base' <<<"$expected")" "content=${content}" \
          "saferemove=$(jq -er '.saferemove' <<<"$expected")" \
          "shared=$(jq -er 'if .shared then 1 else 0 end' <<<"$expected")"
      fi
      ;;
    local_lvm)
      urlencode_pairs \
        "storage=${storage_id}" "type=${type}" \
        "vgname=$(jq -er '.volume_group' <<<"$expected")" \
        "thinpool=$(jq -er '.thin_pool' <<<"$expected")" "content=${content}" \
        "nodes=${nodes}"
      ;;
  esac
}

proxmox_update_body() {
  local expected="$1"
  local kind="$2"
  local content nodes delete_nodes

  content="$(storage_content_csv "$expected")"
  nodes="$(storage_nodes_csv "$expected")"
  delete_nodes="$(storage_nodes_delete_pair "$expected")"
  case "$kind" in
    iscsi)
      if [[ -n "$delete_nodes" ]]; then
        urlencode_pairs "content=${content}" "$delete_nodes"
      else
        urlencode_pairs "content=${content}"
      fi
      ;;
    lvm)
      if [[ -n "$delete_nodes" ]]; then
        urlencode_pairs "content=${content}" \
          "saferemove=$(jq -er '.saferemove' <<<"$expected")" \
          "shared=$(jq -er 'if .shared then 1 else 0 end' <<<"$expected")" \
          "$delete_nodes"
      elif [[ -n "$nodes" ]]; then
        urlencode_pairs "content=${content}" \
          "saferemove=$(jq -er '.saferemove' <<<"$expected")" \
          "shared=$(jq -er 'if .shared then 1 else 0 end' <<<"$expected")" \
          "nodes=${nodes}"
      else
        urlencode_pairs "content=${content}" \
          "saferemove=$(jq -er '.saferemove' <<<"$expected")" \
          "shared=$(jq -er 'if .shared then 1 else 0 end' <<<"$expected")"
      fi
      ;;
    local_lvm)
      if [[ -n "$delete_nodes" ]]; then
        urlencode_pairs "content=${content}" "$delete_nodes"
      else
        urlencode_pairs "content=${content}" "nodes=${nodes}"
      fi
      ;;
  esac
}

proxmox_validate_contract() {
  local expected kind storage_id live

  # Validate every declared identity before any Proxmox or Synology write. This
  # prevents a partial drift correction from preceding a later identity guard.
  for kind in iscsi lvm local_lvm; do
    expected="$(jq -c ".proxmox.storages.${kind}" <<<"${desired_json}")"
    storage_id="$(jq -er '.id' <<<"${expected}")"
    [[ "${storage_id}" =~ ^[A-Za-z0-9_-]+$ ]] || fail "unsafe Proxmox storage identifier"
    live="$(proxmox_storage_entry "${storage_id}" || true)"
    if [[ -z "${live}" ]]; then
      if [[ "${kind}" == local_lvm ]]; then
        fail "declared local-lvm storage is absent; refusing to create a node-local storage entry"
      fi
      proxmox_storage_missing=1
    else
      storage_identity_matches "${live}" "${expected}" "${kind}" || fail "Proxmox storage ${storage_id} has an unexpected identity"
    fi
  done
}

proxmox_reconcile_storage() {
  local expected="$1"
  local kind="$2"
  local storage_id live body response
  storage_id="$(jq -er '.id' <<<"$expected")"
  [[ "$storage_id" =~ ^[A-Za-z0-9_-]+$ ]] || fail "unsafe Proxmox storage identifier"

  live="$(proxmox_storage_entry "$storage_id" || true)"
  if [[ -z "$live" ]]; then
    if [[ "$kind" == local_lvm ]]; then
      fail "declared local-lvm storage is absent; refusing to create a node-local storage entry"
    fi
    if [[ "$mode" == check ]]; then
      echo "Proxmox storage ${storage_id} is absent and would be created by apply."
      proxmox_storage_missing=1
      return
    fi
    body="$(proxmox_create_body "$expected" "$kind")"
    response="$(proxmox_request POST "${proxmox_endpoint}/storage" "$body")" || fail "could not create Proxmox storage ${storage_id}"
    proxmox_response_ok "$response" || fail "Proxmox rejected creation of storage ${storage_id}"
    refresh_proxmox_storage
    live="$(proxmox_storage_entry "$storage_id" || true)"
    [[ -n "$live" ]] || fail "Proxmox storage ${storage_id} was not returned after creation"
  fi

  storage_identity_matches "$live" "$expected" "$kind" || fail "Proxmox storage ${storage_id} has an unexpected identity"
  if ! storage_contract_matches "$live" "$expected" "$kind"; then
    if [[ "$mode" == check ]]; then
      echo "Proxmox storage ${storage_id} differs from the declared mutable settings."
    else
      body="$(proxmox_update_body "$expected" "$kind")"
      response="$(proxmox_request PUT "${proxmox_endpoint}/storage/${storage_id}" "$body")" || fail "could not update Proxmox storage ${storage_id}"
      proxmox_response_ok "$response" || fail "Proxmox rejected update of storage ${storage_id}"
      refresh_proxmox_storage
      live="$(proxmox_storage_entry "$storage_id" || true)"
      storage_contract_matches "$live" "$expected" "$kind" || fail "Proxmox storage ${storage_id} did not converge"
    fi
  fi
}

proxmox_verify_active() {
  local lvm_id iscsi_id node storage_id status
  iscsi_id="$(jq -er '.proxmox.storages.iscsi.id' <<<"$desired_json")"
  lvm_id="$(jq -er '.proxmox.storages.lvm.id' <<<"$desired_json")"

  while IFS= read -r node; do
    [[ "$node" =~ ^[A-Za-z0-9_-]+$ ]] || fail "unsafe Proxmox node identifier"
    for storage_id in "$iscsi_id" "$lvm_id"; do
      status="$(proxmox_request GET "${proxmox_endpoint}/nodes/${node}/storage/${storage_id}/status")" || fail "could not read ${storage_id} status on ${node}"
      jq -e '(.data.active == true) or (.data.active == 1)' >/dev/null <<<"$status" || fail "storage ${storage_id} is not active on ${node}"
    done
  done < <(jq -r '.proxmox.nodes[]' <<<"$desired_json")
}

synology_request() {
  local body="$1"

  # The DSM password and session token stay in environment-backed curl config;
  # neither appears in command arguments, generated files, or normal output.
  REQUEST_BODY="$body" REQUEST_URL="$synology_api_url" \
    jq -nr '
      "url = " + ($ENV.REQUEST_URL | @json),
      "request = \"POST\"",
      "fail",
      "silent",
      "show-error",
      "connect-timeout = 10",
      "max-time = 60",
      "cookie = " + ($ENV.SYNOLOGY_COOKIE_FILE | @json),
      "cookie-jar = " + ($ENV.SYNOLOGY_COOKIE_FILE | @json),
      "header = \"Content-Type: application/x-www-form-urlencoded\"",
      (if ($ENV.SYNOLOGY_TOKEN // "") == "" then empty else "header = " + (("X-SYNO-TOKEN: " + $ENV.SYNOLOGY_TOKEN) | @json) end),
      "data = " + ($ENV.REQUEST_BODY | @json)
    ' | curl --config -
}

export SYNOLOGY_COOKIE_FILE="$cookie_file"
export SYNOLOGY_TOKEN=""
export SYNOLOGY_SID=""

synology_response_ok() {
  # DSM reports API-level failures inside a successful HTTP response, so both
  # the transport and the JSON success flag must be checked.
  jq -e '.success == true' >/dev/null <<<"$1"
}

synology_form_body() {
  # JSON-valued DSM parameters are compacted here and then form-encoded. The
  # password is used only for the login body and is never passed as an argv.
  python3 - <<'PY'
import json
import os
import urllib.parse

values = {
    "api": os.environ["SYNO_API"],
    "version": os.environ["SYNO_VERSION"],
    "method": os.environ["SYNO_METHOD"],
    "_sid": os.environ.get("SYNOLOGY_SID", ""),
    "SynoToken": os.environ.get("SYNOLOGY_TOKEN", ""),
}
for key, value in json.loads(os.environ.get("SYNO_PARAMS_JSON", "{}")).items():
    if isinstance(value, (dict, list)):
        value = json.dumps(value, separators=(",", ":"))
    values[key] = str(value)
print(urllib.parse.urlencode(values))
PY
}

synology_call() {
  local api="$1"
  local method="$2"
  local version="$3"
  local params_json="${4:-{}}"
  local body

  export SYNO_API="$api" SYNO_METHOD="$method" SYNO_VERSION="$version" SYNO_PARAMS_JSON="$params_json"
  body="$(synology_form_body)"
  synology_request "$body"
}

synology_login() {
  local login_body login_response

  # Build the login form in a child process that reads the password from its
  # environment. No password-bearing string is put in a shell argument.
  login_body="$(python3 - <<'PY'
import os
import urllib.parse

print(urllib.parse.urlencode({
    "api": "SYNO.API.Auth",
    "version": "7",
    "method": "login",
    "account": os.environ["SYNOLOGY_USERNAME"],
    "passwd": os.environ["SYNOLOGY_PASSWORD"],
    "session": "FileStation",
    "format": "sid",
    "enable_syno_token": "yes",
}))
PY
  )" || fail "could not build Synology login request"
  login_response="$(synology_request "$login_body")" || fail "Synology login request failed"
  synology_response_ok "$login_response" || fail "Synology login was rejected"
  SYNOLOGY_SID="$(jq -er '.data.sid' <<<"$login_response")" || fail "Synology login did not return a session id"
  SYNOLOGY_TOKEN="$(jq -er '.data.synotoken' <<<"$login_response")" || fail "Synology login did not return a SynoToken"
  export SYNOLOGY_SID SYNOLOGY_TOKEN
}

synology_entry_request() {
  local compound="$1"
  synology_call "SYNO.Entry.Request" "request" 2 "$(jq -cn --argjson compound "$compound" '{params:$compound}')"
}

synology_entry_response_ok() {
  # DSM can return HTTP 200 and a top-level success flag while reporting a
  # failed nested compound operation. Reject either level before continuing.
  jq -e '
    .success == true
    and (
      (.data.result // .data.results // [])
      | if type == "array" then
          all(.[];
            (.success == null or .success == true)
            and (.error == null)
            and (.errors == null)
          )
        else true
        end
    )
  ' >/dev/null <<<"$1"
}

synology_target_json=""
synology_host_json=""

synology_validate_contract() {
  local target_list host_list target host desired_iqns target_id host_id lun_uuid permission
  target_id="$(jq -er '.synology.target_id' <<<"$desired_json")"
  host_id="$(jq -er '.synology.host_id' <<<"$desired_json")"
  lun_uuid="$(jq -er '.synology.lun_uuid' <<<"$desired_json")"
  permission="$(jq -er '.synology.permission' <<<"$desired_json")"
  desired_iqns="$(jq -c '.synology.initiator_iqns' <<<"$desired_json")"

  target_list="$(synology_call "SYNO.Core.ISCSI.Target" "list" 1 '{"additional":["mapped_lun","connected_sessions","status"]}')" || fail "could not read Synology iSCSI targets"
  synology_response_ok "$target_list" || fail "Synology target inventory request was rejected"
  target="$(jq -ce --arg id "$target_id" '[.data.targets[]? | select((.target_id | tostring) == $id)] | if length == 1 then .[0] else empty end' <<<"$target_list" || true)"
  [[ -n "$target" ]] || fail "declared Synology target identity was not found uniquely"
  jq -e --arg name "$(jq -er '.synology.target_name' <<<"$desired_json")" --arg iqn "$(jq -er '.synology.target_iqn' <<<"$desired_json")" --arg lun "$lun_uuid" '
    .name == $name
    and .iqn == $iqn
    and any(.mapped_luns[]?; (.lun_uuid | tostring) == $lun)
  ' >/dev/null <<<"$target" || fail "Synology target identity or LUN mapping is unexpected"

  if [[ "$(jq -r '.max_sessions | tostring' <<<"$target")" != "$(jq -r '.synology.target_max_sessions | tostring' <<<"$desired_json")" ]]; then
    echo "Synology target ${target_id} has a different session limit and would be updated by apply."
  fi

  host_list="$(synology_call "SYNO.Core.ISCSI.Host" "list" 1 '{"additional":["acls"]}')" || fail "could not read Synology iSCSI hosts"
  synology_response_ok "$host_list" || fail "Synology host inventory request was rejected"
  host="$(jq -ce --arg id "$host_id" '[.data.hosts[]? | select((.host_id | tostring) == $id)] | if length == 1 then .[0] else empty end' <<<"$host_list" || true)"
  [[ -n "$host" ]] || fail "declared Synology host identity was not found uniquely"
  jq -e --arg lun "$lun_uuid" --arg permission "$permission" --argjson desired "$desired_iqns" '
    ([.acls[]? | select((.lun_uuid | tostring) == $lun)] as $acl
      | ($acl | length) == 1
      and $acl[0].permission == $permission)
    and all(.initiator_ids[]?; . as $current | ($desired | index($current)) != null)
  ' >/dev/null <<<"$host" || fail "Synology host has an unexpected ACL or initiator"

  while IFS= read -r iqn; do
    [[ -n "$iqn" ]] || continue
    if jq -e --arg iqn "$iqn" 'any(.initiator_ids[]?; . == $iqn)' >/dev/null <<<"$host"; then
      continue
    fi
    if [[ "$mode" == check ]]; then
      echo "Synology host ${host_id} is missing declared initiator ${iqn} and would be updated by apply."
    else
      echo "Synology host ${host_id} is missing a declared initiator and would be updated by apply."
    fi
  done < <(jq -r '.[]' <<<"$desired_iqns")

  # Preserve only the already-validated, non-secret objects for the immediate
  # mutation phase. No write is possible until both target and host checks pass.
  synology_target_json="$target"
  synology_host_json="$host"
}

synology_reconcile_contract() {
  local target_id host_id target_set target_response map_request map_response iqn
  target_id="$(jq -er '.synology.target_id' <<<"${desired_json}")"
  host_id="$(jq -er '.synology.host_id' <<<"${desired_json}")"

  if [[ "$(jq -r '.max_sessions | tostring' <<<"${synology_target_json}")" != "$(jq -r '.synology.target_max_sessions | tostring' <<<"${desired_json}")" ]]; then
    target_set="$(jq -cn --arg id "${target_id}" --argjson max "$(jq -er '.synology.target_max_sessions' <<<"${desired_json}")" '{stopwhenerror:true,mode:"sequential",params:[{api:"SYNO.Core.ISCSI.Target",method:"set",version:1,params:{target_id:$id,max_sessions:$max}}]}')"
    target_response="$(synology_entry_request "${target_set}")" || fail "Synology target session-limit request failed"
    synology_entry_response_ok "${target_response}" || fail "Synology target session-limit update failed"
  fi

  while IFS= read -r iqn; do
    [[ -n "${iqn}" ]] || continue
    if jq -e --arg iqn "${iqn}" 'any(.initiator_ids[]?; . == $iqn)' >/dev/null <<<"${synology_host_json}"; then
      continue
    fi
    map_request="$(jq -cn --arg id "${host_id}" --arg iqn "${iqn}" '{stopwhenerror:true,mode:"sequential",params:[{api:"SYNO.Core.ISCSI.Host",method:"map_initiator",version:1,params:{host_id:$id,initiator_ids:[$iqn]}}]}')"
    map_response="$(synology_entry_request "${map_request}")" || fail "Synology initiator mapping request failed"
    synology_entry_response_ok "${map_response}" || fail "Synology initiator mapping failed"
  done < <(jq -r '.synology.initiator_iqns[]' <<<"${desired_json}")
}

synology_verify_final() {
  local target_list host_list target host target_id host_id lun_uuid desired_iqns
  target_id="$(jq -er '.synology.target_id' <<<"$desired_json")"
  host_id="$(jq -er '.synology.host_id' <<<"$desired_json")"
  lun_uuid="$(jq -er '.synology.lun_uuid' <<<"$desired_json")"
  desired_iqns="$(jq -c '.synology.initiator_iqns' <<<"$desired_json")"
  target_list="$(synology_call "SYNO.Core.ISCSI.Target" "list" 1 '{"additional":["mapped_lun","connected_sessions","status"]}')" || fail "could not verify Synology target"
  host_list="$(synology_call "SYNO.Core.ISCSI.Host" "list" 1 '{"additional":["acls"]}')" || fail "could not verify Synology host"
  target="$(jq -ce --arg id "$target_id" '[.data.targets[]? | select((.target_id | tostring) == $id)] | if length == 1 then .[0] else empty end' <<<"$target_list" || true)"
  host="$(jq -ce --arg id "$host_id" '[.data.hosts[]? | select((.host_id | tostring) == $id)] | if length == 1 then .[0] else empty end' <<<"$host_list" || true)"
  [[ -n "$target" && -n "$host" ]] || fail "Synology postcondition identities are missing"
  jq -e --arg lun "$lun_uuid" --argjson desired "$desired_iqns" --argjson max "$(jq -er '.synology.target_max_sessions' <<<"$desired_json")" '
    (.max_sessions == $max)
    and any(.mapped_luns[]?; (.lun_uuid | tostring) == $lun)
    and all(.connected_sessions[]?; (.iqn | tostring) as $iqn | ($desired | index($iqn)) != null)
    and ([.connected_sessions[]? | .iqn] | unique | length) >= ($desired | length)
  ' >/dev/null <<<"$target" || fail "Synology target postconditions are not satisfied"
  jq -e --arg lun "$lun_uuid" --arg permission "$(jq -er '.synology.permission' <<<"$desired_json")" --argjson desired "$desired_iqns" '
    ([.acls[]? | select((.lun_uuid | tostring) == $lun)] as $acl
      | ($acl | length) == 1
      and $acl[0].permission == $permission)
    and (([.initiator_ids[]?] | sort) == ($desired | sort))
  ' >/dev/null <<<"$host" || fail "Synology host postconditions are not satisfied"
}

proxmox_storage_missing=0
synology_login
synology_validate_contract

refresh_proxmox_storage
proxmox_validate_contract

if [[ "$mode" == apply ]]; then
  # All Synology and Proxmox identities have passed their read-only guards
  # before this first mutation is allowed to run.
  synology_reconcile_contract
fi

proxmox_reconcile_storage "$(jq -c '.proxmox.storages.iscsi' <<<"$desired_json")" iscsi
proxmox_reconcile_storage "$(jq -c '.proxmox.storages.lvm' <<<"$desired_json")" lvm
proxmox_reconcile_storage "$(jq -c '.proxmox.storages.local_lvm' <<<"$desired_json")" local_lvm

if [[ "$mode" == apply ]]; then
  synology_verify_final
  proxmox_verify_active
  echo "Proxmox and Synology shared iSCSI storage converged and passed post-apply verification."
elif (( proxmox_storage_missing == 0 )); then
  # The live configuration is part of the plan preflight. Mutable drift is
  # permitted here, but an already-declared shared storage that is inactive is
  # not a safe target for an immutable production apply.
  proxmox_verify_active
  echo "Proxmox and Synology shared iSCSI storage passed read-only preflight."
else
  echo "Proxmox and Synology storage preflight passed identity checks; apply would create the missing shared entries."
fi
