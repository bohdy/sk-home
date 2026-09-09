#!/usr/bin/env bash

# Reconcile only the RouterOS-native qnetd mount and container objects that
# the pinned provider cannot write on RouterOS 7.23. The caller must apply the
# reviewed provider plan before invoking this script so the state-only desired
# records and provider-managed prerequisites already exist.
set -euo pipefail
umask 077

: "$MIKROTIK_USERNAME"
: "$MIKROTIK_PASSWORD"
: "$ROUTEROS_URL"
: "$STACK_PATH"

# Keep the single raw response file private and remove it on every exit path,
# including cancellation while curl is receiving an HTTP error response.
routeros_response_dir="$(mktemp -d)"
routeros_response_file="${routeros_response_dir}/response.json"
cleanup_routeros_response() {
  rm -f -- "$routeros_response_file"
  rmdir -- "$routeros_response_dir"
}
trap cleanup_routeros_response EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 143' TERM

# Use curl's stdin configuration so credentials never appear in process
# arguments, logs, or repository files. Responses are kept in a temporary file
# so HTTP failures can be classified without printing a potentially sensitive
# RouterOS error body.
routeros_error_class() {
  local response_file="$1"

  jq -r '
    if type != "object" then
      "unstructured"
    else
      [ .message, .detail ]
      | map(select(type == "string"))
      | join(" ") as $detail
      | if ($detail | length) == 0 then
          "none"
        elif ($detail | test("unknown parameter|unknown property|no such command|invalid parameter"; "i")) then
          "parameter"
        elif ($detail | test("remote-image|image|registry|manifest|repository|pull|resolve|architecture"; "i")) then
          "image-or-registry"
        elif ($detail | test("root-dir|root directory|layer-dir|tmpdir|storage|disk|directory|path|space"; "i")) then
          "storage-path"
        elif ($detail | test("mountlists|mount list|mount|list"; "i")) then
          "mount-list"
        elif ($detail | test("interface|veth|network"; "i")) then
          "network"
        elif ($detail | test("name|tag"; "i")) then
          "name"
        elif ($detail | test("permission|denied|not permitted|authoriz"; "i")) then
          "permission"
        else
          "other"
        end
    end
  ' "$response_file" 2>/dev/null || printf '%s\n' 'unstructured'
}

routeros_request() {
  local method="$1"
  local url="$2"
  local payload=${3-}
  local endpoint="${url#"$ROUTEROS_URL"}"
  local http_code
  local response

  # Keep the response private while identifying the endpoint on transport or
  # HTTP failure; raw RouterOS errors may contain configuration data.
  if ! http_code="$(
    REQUEST_METHOD="$method" REQUEST_URL="$url" REQUEST_PAYLOAD="$payload" \
      jq -nr '
        "user = " + (($ENV.MIKROTIK_USERNAME + ":" + $ENV.MIKROTIK_PASSWORD) | @json),
        "url = " + ($ENV.REQUEST_URL | @json),
        "request = " + ($ENV.REQUEST_METHOD | @json),
        "insecure",
        "silent",
        "show-error",
        "header = " + ("Content-Type: application/json" | @json),
        (if ($ENV.REQUEST_PAYLOAD // "") == "" then empty else "data = " + ($ENV.REQUEST_PAYLOAD | @json) end)
      ' | curl --config - --output "$routeros_response_file" --write-out '%{http_code}'
  )"; then
    rm -f -- "$routeros_response_file"
    echo "RouterOS request failed: ${method} ${endpoint:-/}." >&2
    return 1
  fi

  if [[ ! "$http_code" =~ ^2[0-9]{2}$ ]]; then
    local error_class
    error_class="$(routeros_error_class "$routeros_response_file")"
    rm -f -- "$routeros_response_file"
    echo "RouterOS request failed: ${method} ${endpoint:-/} (HTTP ${http_code}; error-class=${error_class})." >&2
    return 1
  fi

  response="$(<"$routeros_response_file")"
  rm -f -- "$routeros_response_file"
  printf '%s\n' "$response"
}

ROUTEROS_URL=$(printf '%s' "$ROUTEROS_URL" | sed 's:/*$::')

# The initial immutable plan must have populated these records before native
# recovery. A state-list failure is fatal; only grep's ordinary no-match path
# is handled as a conditional below.
state_list="$(tofu -chdir=terraform/$STACK_PATH state list)"
if legacy_state="$(grep -E '^(routeros_container_mounts\.qdevice|routeros_container\.qdevice)' <<<"$state_list")"; then
  echo "Legacy provider-managed qdevice mount/container state requires a reviewed migration." >&2
  exit 1
fi

require_state_address() {
  local address="$1"

  if grep -Fqx -- "$address" <<<"$state_list"; then
    if ! tofu -chdir=terraform/$STACK_PATH state show "$address" >/dev/null; then
      echo "State lists $address, but state show failed; refusing to continue." >&2
      exit 1
    fi
  else
    echo "Expected qdevice state address $address is absent after the reviewed plan." >&2
    exit 1
  fi
}

for address in \
  'routeros_interface_veth.qdevice[0]' \
  'routeros_interface_bridge_port.qdevice[0]' \
  'routeros_interface_bridge_vlan.bridge_vlan["100"]' \
  'routeros_container_config.qdevice[0]' \
  'routeros_file.qdevice_authorized_keys[0]' \
  'terraform_data.qdevice_mounts[0]' \
  'terraform_data.qdevice_container[0]'; do
  require_state_address "$address"
done

# Read only the two qdevice terraform_data records from state. The full state
# is never assigned to a shell variable or printed, and every native payload
# and verification value below is derived from this reviewed desired state.
qdevice_desired="$(
  tofu -chdir=terraform/$STACK_PATH show -json |
    jq -ce '
      [
        .values.root_module.resources[]?
        | select(
            .address == "terraform_data.qdevice_mounts[0]"
            or .address == "terraform_data.qdevice_container[0]"
          )
        | {address, input: .values.input}
      ] as $records
      | if ($records | length) != 2
        or (($records | map(.address) | sort) != [
          "terraform_data.qdevice_container[0]",
          "terraform_data.qdevice_mounts[0]"
        ]) then
          error("qdevice desired-state records are missing")
        else
          (reduce $records[] as $record ({}; .[$record.address] = $record.input)) as $desired
          | {
              mounts: $desired["terraform_data.qdevice_mounts[0]"],
              container: $desired["terraform_data.qdevice_container[0]"]
            }
        end
    '
)"

# Keep native recovery narrowly bound to the shape declared by qdevice.tf.
# Mount names must match native mountlists exactly and the record must request
# a running, boot-enabled, logged qnetd container.
if ! jq -e '
  def safe_global_path:
    if type != "string" then false
    else test("^/usb1/[^/]+(/[^/]+)*$") and ((split("/") | index("..")) == null)
    end;
  def safe_root_path:
    if type != "string" then false
    else test("^usb1/[^/]+(/[^/]+)*$") and ((split("/") | index("..")) == null)
    end;
  .mounts as $mounts
  | .container as $container
  | if ($mounts | type) != "object"
    or ($container | type) != "object"
    or (($mounts | keys | length) != 3)
    or (($mounts | to_entries | map(select(
      ((.key | type) == "string")
      and ((.value | type) == "object")
      and ((.value.src | type) == "string")
      and ((.value.dst | type) == "string")
      and ((.value.src | length) > 0)
      and ((.value.dst | length) > 0)
    )) | length) != 3)
    or (($container.mountlists | type) != "array")
    or (($container.mountlists | length) != 3)
    or (($container.mountlists | unique | length) != 3)
    or (($container.mountlists | sort) != ($mounts | keys | sort))
    or (($container.name | type) != "string")
    or ($container.name != "qnetd")
    or (($container["remote-image"] | type) != "string")
    or (($container["remote-image"] | length) == 0)
    or (($container.interface | type) != "string")
    or (($container["root-dir"] | safe_root_path) | not)
    or (($container.comment | type) != "string")
    or (($container["start-on-boot"] // false) != true)
    or (($container.logging // false) != true)
    or (($container.running // false) != true)
    or (($container.network | type) != "object")
    or (($container.network.interface_name | type) != "string")
    or (($container.network.interface_name) != ($container.interface))
    or (($container.network.address | type) != "string")
    or (($container.network.gateway | type) != "string")
    or (($container.network.vlan_id | type) != "number")
    or (($container.network.bridge | type) != "string")
    or (($container.network.frame_types | type) != "string")
    or (($container.network.tagged | type) != "array")
    or (($container.network.untagged | type) != "array")
    or (any($container.network.tagged[]?; type != "string"))
    or (any($container.network.untagged[]?; type != "string"))
    or (($container.container_config | type) != "object")
    or (($container.container_config.layer_dir | safe_global_path) | not)
    or (($container.container_config.tmpdir | safe_global_path) | not)
    or (($container.container_config.authorized_key_path | type) != "string") then
      false
    else true
    end
' <<<"$qdevice_desired" >/dev/null; then
  echo "The qdevice desired state is malformed or unsafe for native recovery." >&2
  exit 1
fi

mount_specs="$(jq -ce '.mounts | to_entries | map({list:.key,src:.value.src,dst:.value.dst})' <<<"$qdevice_desired")"
container_spec="$(jq -ce '.container' <<<"$qdevice_desired")"
network_spec="$(jq -ce '.container.network' <<<"$qdevice_desired")"
container_config_spec="$(jq -ce '.container.container_config' <<<"$qdevice_desired")"
qdevice_tagged="$(jq -ce '.tagged' <<<"$network_spec")"
qdevice_untagged="$(jq -ce '.untagged' <<<"$network_spec")"

qdevice_interface="$(jq -er '.interface_name' <<<"$network_spec")"
qdevice_address="$(jq -er '.address' <<<"$network_spec")"
qdevice_gateway="$(jq -er '.gateway' <<<"$network_spec")"
qdevice_vlan="$(jq -er '.vlan_id | tostring' <<<"$network_spec")"
qdevice_bridge="$(jq -er '.bridge' <<<"$network_spec")"
qdevice_frame_types="$(jq -er '.frame_types' <<<"$network_spec")"
qdevice_container_name="$(jq -er '.name' <<<"$container_spec")"
qdevice_image="$(jq -er '."remote-image"' <<<"$container_spec")"
qdevice_layer_dir="$(jq -er '.layer_dir' <<<"$container_config_spec")"
qdevice_tmpdir="$(jq -er '.tmpdir' <<<"$container_config_spec")"

# RouterOS 7.23 exposes runtime state as the string `.stopped` field in the
# REST container collection; retain compatibility with versions that expose
# `.running` or a human-readable `.status` field instead.
container_runtime_status() {
  local container_id="$1"

  jq -r --arg id "$container_id" '
    [ .[] | select(.[".id"] == $id) ]
    | if length != 1 then
        ""
      else
        .[0] as $container
        | if (($container.status // "") | tostring | length) > 0 then
            ($container.status | tostring | ascii_downcase)
          elif (($container.running | tostring | ascii_downcase) == "true") then
            "running"
          elif (($container.running | tostring | ascii_downcase) == "false") then
            "stopped"
          elif (($container.stopped | tostring | ascii_downcase) == "true") then
            "stopped"
          elif (($container.stopped | tostring | ascii_downcase) == "false") then
            "running"
          else
            ""
          end
      end
  '
}

veths=$(routeros_request GET "$ROUTEROS_URL/rest/interface/veth")
ports=$(routeros_request GET "$ROUTEROS_URL/rest/interface/bridge/port")
vlans=$(routeros_request GET "$ROUTEROS_URL/rest/interface/bridge/vlan")
files=$(routeros_request GET "$ROUTEROS_URL/rest/file")
mounts=$(routeros_request GET "$ROUTEROS_URL/rest/container/mounts")
containers=$(routeros_request GET "$ROUTEROS_URL/rest/container")
container_config=$(routeros_request GET "$ROUTEROS_URL/rest/container/config")

if ! jq -e 'type == "array"' <<<"$mounts" >/dev/null ||
   ! jq -e 'type == "array"' <<<"$containers" >/dev/null ||
   ! jq -e 'type == "array"' <<<"$files" >/dev/null ||
   ! jq -e 'type == "array"' <<<"$veths" >/dev/null ||
   ! jq -e 'type == "array"' <<<"$ports" >/dev/null ||
   ! jq -e 'type == "array"' <<<"$vlans" >/dev/null ||
   ! jq -e 'type == "object"' <<<"$container_config" >/dev/null; then
  echo "RouterOS returned a malformed qdevice collection or configuration response." >&2
  exit 1
fi

# Recheck the adopted prerequisites after the production gate so a stale
# initial plan cannot authorize recovery against a changed gateway.
if ! jq -e --arg interface "$qdevice_interface" --arg address "$qdevice_address" --arg gateway "$qdevice_gateway" '
  [.[] | select(.name == $interface)] as $matches
  | ($matches | length == 1)
    and ($matches[0].address == $address)
    and ($matches[0].gateway == $gateway)
' <<<"$veths" >/dev/null; then
  echo "The qdevice veth no longer matches the reviewed network declaration." >&2
  exit 1
fi
if ! jq -e --arg interface "$qdevice_interface" --arg bridge "$qdevice_bridge" --arg pvid "$qdevice_vlan" --arg frame_types "$qdevice_frame_types" '
  [.[] | select(.interface == $interface)] as $matches
  | ($matches | length == 1)
    and ($matches[0].bridge == $bridge)
    and (($matches[0].pvid | tostring) == $pvid)
    and ($matches[0]["frame-types"] == $frame_types)
' <<<"$ports" >/dev/null; then
  echo "The qdevice bridge port no longer matches the reviewed VLAN declaration." >&2
  exit 1
fi
if ! jq -e --arg interface "$qdevice_interface" --arg bridge "$qdevice_bridge" --arg vlan "$qdevice_vlan" --argjson desired_tagged "$qdevice_tagged" --argjson desired_untagged "$qdevice_untagged" '
  def members($value):
    if $value == null then []
    elif ($value | type) == "array" then $value
    elif ($value | type) == "string" then ($value | split(",") | map(select(length > 0)))
    else []
    end;
  def occurrences($value; $member):
    [members($value)[] | select(. == $member)] | length;
  def vlan_ids($value): members($value);
  . as $all
  | [ $all[] | select(.bridge == $bridge and (vlan_ids(.["vlan-ids"]) == [$vlan])) ] as $matches
  | ([ $all[] | occurrences(.untagged; $interface) ] | add // 0) as $untagged_occurrences
  | ([ $all[] | occurrences(.tagged; $interface) ] | add // 0) as $tagged_occurrences
  | ($matches | length == 1)
    and ((members($matches[0].tagged) | sort) == ($desired_tagged | sort))
    and ((members($matches[0].untagged) | sort) == ($desired_untagged | sort))
    and (occurrences($matches[0].untagged; $interface) == 1)
    and (occurrences($matches[0].tagged; $interface) == 0)
    and ($untagged_occurrences == 1)
    and ($tagged_occurrences == 0)
' <<<"$vlans" >/dev/null; then
  echo "The qdevice VLAN 100 attachment no longer matches the reviewed declaration." >&2
  exit 1
fi

verify_state_identity() {
  local address="$1"
  local expected_id="$2"
  local state_id

  state_id="$(tofu -chdir=terraform/$STACK_PATH state show -no-color "$address" | awk '$1 == "id" && $2 == "=" {gsub(/^\"|\"$/, "", $3); print $3; exit}')"
  if [[ -z "$state_id" || "$state_id" != "$expected_id" ]]; then
    echo "State identity for $address does not match the live RouterOS object; refusing to continue." >&2
    exit 1
  fi
}

veth_id="$(jq -er --arg interface "$qdevice_interface" '[.[] | select(.name == $interface)] | if length == 1 then .[0][".id"] else error("qdevice veth identity is unavailable") end' <<<"$veths")"
port_id="$(jq -er --arg interface "$qdevice_interface" '[.[] | select(.interface == $interface)] | if length == 1 then .[0][".id"] else error("qdevice bridge-port identity is unavailable") end' <<<"$ports")"
vlan_id="$(jq -er --arg bridge "$qdevice_bridge" --arg vlan "$qdevice_vlan" '[.[] | select(.bridge == $bridge and (.["vlan-ids"] | tostring) == $vlan)] | if length == 1 then .[0][".id"] else error("qdevice VLAN identity is unavailable") end' <<<"$vlans")"
verify_state_identity 'routeros_interface_veth.qdevice[0]' "$veth_id"
verify_state_identity 'routeros_interface_bridge_port.qdevice[0]' "$port_id"
verify_state_identity 'routeros_interface_bridge_vlan.bridge_vlan["100"]' "$vlan_id"

required_paths="$(jq -ce '
  [
    (.container["root-dir"] | split("/") | .[0:-1] | join("/")),
    (.container.container_config.layer_dir | sub("^/+"; "")),
    (.container.container_config.tmpdir | sub("^/+"; "")),
    (.mounts | to_entries[] | .value.src)
  ] | map(select(length > 0)) | unique
' <<<"$qdevice_desired")"
if ! jq -e --argjson required "$required_paths" '
  . as $files
  | all($required[]; . as $path | any($files[]; .name == $path and .type == "directory"))
' <<<"$files" >/dev/null; then
  echo "One or more reviewed qdevice USB directories are missing or not directories." >&2
  exit 1
fi
if ! jq -e --arg layer_dir "$qdevice_layer_dir" --arg tmpdir "$qdevice_tmpdir" '
  (type == "object")
  and (.["layer-dir"] | type) == "string"
  and (.tmpdir | type) == "string"
  and .["layer-dir"] == $layer_dir
  and .tmpdir == $tmpdir
' <<<"$container_config" >/dev/null; then
  echo "RouterOS global container extraction paths do not match the reviewed qdevice declaration." >&2
  exit 1
fi
if ! jq -e '
  . as $config
  | if (type != "object")
    or ((($config["registry-url"] // $config.registry_url // "") | type) != "string")
    or ((($config["assumed-registry-url"] // "") | type) != "string") then
      false
    else
      ($config["registry-url"] // $config.registry_url // "") as $registry
      | ($config["assumed-registry-url"] // "") as $assumed
      | (["", "docker.io", "registry-1.docker.io", "https://registry-1.docker.io"] | index($registry) != null)
        and (["", "docker.io", "registry-1.docker.io"] | index($assumed) != null)
    end
' <<<"$container_config" >/dev/null; then
  echo "RouterOS global container registry configuration is malformed or not Docker Hub." >&2
  exit 1
fi

# RouterOS creates the root-dir store during /container/add. A prior failed
# attempt or manual preparation may leave the exact empty placeholder behind;
# remove only that placeholder and refuse any directory containing data. An
# existing exact qnetd container may already own the path as a container store.
root_dir_matches="$(jq -c --arg root_dir "$(jq -er '."root-dir"' <<<"$container_spec")" '[.[] | select(.name == $root_dir)]' <<<"$files")"
root_dir_count="$(jq -er 'length' <<<"$root_dir_matches")"
if [[ "$root_dir_count" -gt 1 ]] ||
   [[ "$root_dir_count" == 1 && "$(jq -er '.[0].type' <<<"$root_dir_matches")" != directory && "$(jq -er '.[0].type' <<<"$root_dir_matches")" != 'container store' ]]; then
  echo "The reviewed RouterOS qnetd root-dir path is not a supported directory or container store." >&2
  exit 1
fi
root_dir="$(jq -er '."root-dir"' <<<"$container_spec")"
root_dir_type="$(jq -er '.[0].type' <<<"$root_dir_matches" 2>/dev/null || true)"
if [[ "$root_dir_type" == directory ]]; then
  root_dir_children="$(jq -er --arg root_dir "$root_dir" '[.[] | select((.name // "") | startswith($root_dir + "/"))] | length' <<<"$files")"
  if [[ "$root_dir_children" != 0 ]]; then
    echo "The reviewed RouterOS qnetd root-dir placeholder contains data; refusing to remove it." >&2
    exit 1
  fi
  root_dir_id="$(jq -er '.[0][".id"]' <<<"$root_dir_matches")"
  routeros_request DELETE "$ROUTEROS_URL/rest/file/$root_dir_id" >/dev/null
  files=$(routeros_request GET "$ROUTEROS_URL/rest/file")
  if ! jq -e --arg root_dir "$root_dir" 'all(.[]; .name != $root_dir and (((.name // "") | startswith($root_dir + "/")) | not))' <<<"$files" >/dev/null; then
    echo "RouterOS did not remove the exact empty qnetd root-dir placeholder." >&2
    exit 1
  fi
  echo "Removed the exact empty RouterOS qnetd root-dir placeholder before container creation."
elif [[ "$root_dir_type" == 'container store' ]]; then
  # An existing exact qnetd container owns this store, so preserve it and let
  # the idempotent mount and runtime checks continue without deleting data.
  echo "Preserving the existing RouterOS qnetd container store."
fi

# Existing mount rows may be absent or an exact subset of the desired set so
# an interrupted recovery can resume. Any unrelated, duplicate, or mismatched
# row is a conflict and is never overwritten. RouterOS reports native USB
# mount sources with one leading slash; canonicalize only that representation
# for comparison while leaving the reviewed payload unchanged.
if ! jq -e --argjson required "$mount_specs" '
  def canonical_native_src:
    if type == "string" and startswith("/usb1/") then .[1:] else . end;
  . as $mounts
  | (type == "array")
    and all($mounts[];
      . as $actual
      | (type == "object")
        and (($actual.list | type) == "string")
        and (($actual.src | type) == "string")
        and (($actual.dst | type) == "string")
        and (($actual.list | length) > 0)
        and (($actual.src | length) > 0)
        and (($actual.dst | length) > 0)
        and any($required[];
          .list == $actual.list
          and .src == ($actual.src | canonical_native_src)
          and .dst == $actual.dst
        )
    )
    and (($mounts | map(.list) | unique | length) == ($mounts | length))
' <<<"$mounts" >/dev/null; then
  echo "Existing RouterOS mounts conflict with qnetd." >&2
  exit 1
fi

# The global container service is shared state. Permit only an empty service
# or one exact existing qnetd record; unrelated containers are a hard stop.
if ! jq -e --argjson wanted "$container_spec" '
  def values:
    if . == null then []
    elif type == "array" then .
    elif type == "string" then split(",") | map(select(length > 0))
    else []
    end;
  def canonical_root_path:
    if type == "string" and startswith("/usb1/") then .[1:] else . end;
  def truthy:
    tostring | ascii_downcase as $value | ["true", "yes", "on", "1"] | index($value) != null;
  . as $containers
  | if ($containers | type) != "array" then false
    elif ($containers | length) == 0 then true
    elif ($containers | length) != 1 then false
    elif ([ $containers[] | select((.["remote-image"] // "") == $wanted["remote-image"]) ] | length) != 1 then false
    else
      .[0] as $actual
      | ($actual["remote-image"] // "") == $wanted["remote-image"]
        and ($actual.interface // "") == $wanted.interface
        and (($actual["root-dir"] // "") | canonical_root_path) == ($wanted["root-dir"] | canonical_root_path)
        and ($actual.name // "") == $wanted.name
        and (($actual.mountlists // []) | values | sort) == ($wanted.mountlists | sort)
        and (($actual["start-on-boot"] // false) | truthy)
        and (($actual.logging // false) | truthy)
        and ($actual.comment // "") == $wanted.comment
    end
' <<<"$containers" >/dev/null; then
  echo "Existing RouterOS containers conflict with qnetd." >&2
  exit 1
fi

while IFS= read -r mount_spec; do
  mount_list=$(jq -er '.list' <<<"$mount_spec")
  mount_count=$(jq --arg list "$mount_list" '[.[] | select(.list == $list)] | length' <<<"$mounts")
  if [[ "$mount_count" == 0 ]]; then
    # RouterOS 7.23 accepts list/src/dst; the provider's name/src/dst payload
    # is the incompatibility this narrowly scoped recovery avoids.
    routeros_request POST "$ROUTEROS_URL/rest/container/mounts/add" "$mount_spec" >/dev/null
    mounts=$(routeros_request GET "$ROUTEROS_URL/rest/container/mounts")
    if ! jq -e 'type == "array"' <<<"$mounts" >/dev/null; then
      echo "RouterOS returned a malformed mount collection after creation." >&2
      exit 1
    fi
  elif [[ "$mount_count" != 1 ]] || ! jq -e --argjson wanted "$mount_spec" '
    def canonical_native_src:
      if type == "string" and startswith("/usb1/") then .[1:] else . end;
    any(.[];
      .list == $wanted.list
      and ($wanted.src == (.src | canonical_native_src))
      and .dst == $wanted.dst
    )
  ' <<<"$mounts" >/dev/null; then
    echo "The RouterOS mount $mount_list is conflicting or duplicated." >&2
    exit 1
  fi
done < <(jq -c '.[]' <<<"$mount_specs")

containers=$(routeros_request GET "$ROUTEROS_URL/rest/container")
if ! jq -e 'type == "array"' <<<"$containers" >/dev/null; then
  echo "RouterOS returned a malformed container collection before creation." >&2
  exit 1
fi
if ! jq -e --argjson wanted "$container_spec" '
  def values:
    if . == null then []
    elif type == "array" then .
    elif type == "string" then split(",") | map(select(length > 0))
    else []
    end;
  def canonical_root_path:
    if type == "string" and startswith("/usb1/") then .[1:] else . end;
  def truthy:
    tostring | ascii_downcase as $value | ["true", "yes", "on", "1"] | index($value) != null;
  . as $containers
  | if ($containers | length) == 0 then true
    elif ($containers | length) != 1 then false
    else
      .[0] as $actual
      | ($actual["remote-image"] // "") == $wanted["remote-image"]
        and ($actual.interface // "") == $wanted.interface
        and (($actual["root-dir"] // "") | canonical_root_path) == ($wanted["root-dir"] | canonical_root_path)
        and ($actual.name // "") == $wanted.name
        and (($actual.mountlists // []) | values | sort) == ($wanted.mountlists | sort)
        and (($actual["start-on-boot"] // false) | truthy)
        and (($actual.logging // false) | truthy)
        and ($actual.comment // "") == $wanted.comment
    end
' <<<"$containers" >/dev/null; then
  echo "The RouterOS container set changed during recovery; refusing to create qnetd." >&2
  exit 1
fi
container_id=$(jq -r --arg image "$qdevice_image" --arg name "$qdevice_container_name" '[.[] | select(((.["remote-image"] // "") == $image) and ((.name // "") == $name))] | if length == 1 then .[0][".id"] else "" end' <<<"$containers")
if [[ -z "$container_id" ]]; then
  container_payload="$(jq -cn --argjson wanted "$container_spec" '{
    name: $wanted.name,
    "remote-image": $wanted["remote-image"],
    interface: $wanted.interface,
    "root-dir": $wanted["root-dir"],
    mountlists: ($wanted.mountlists | join(",")),
    "start-on-boot": (if $wanted["start-on-boot"] then "yes" else "no" end),
    logging: (if $wanted.logging then "yes" else "no" end),
    comment: $wanted.comment
  }')"
  routeros_request POST "$ROUTEROS_URL/rest/container/add" "$container_payload" >/dev/null
fi

# Image extraction is asynchronous; wait for a startable object before the
# native start action. The bounded loop fails closed rather than retrying add.
for attempt in $(seq 1 60); do
  containers=$(routeros_request GET "$ROUTEROS_URL/rest/container")
  if ! jq -e 'type == "array"' <<<"$containers" >/dev/null; then
    echo "RouterOS returned a malformed container collection while extracting the image." >&2
    exit 1
  fi
  container_id=$(jq -r --arg image "$qdevice_image" --arg name "$qdevice_container_name" '[.[] | select(((.["remote-image"] // "") == $image) and ((.name // "") == $name))] | if length == 1 then .[0][".id"] else "" end' <<<"$containers")
  container_status="$(container_runtime_status "$container_id" <<<"$containers")"
  if [[ -n "$container_id" ]] && [[ "$container_status" =~ ^(stopped|running)$ ]]; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    echo "RouterOS qnetd image extraction did not finish." >&2
    exit 1
  fi
  sleep 5
done

container_status_lower="$container_status"

public_key_file="terraform/$STACK_PATH/qdevice-authorized.pub"
# Command substitution strips trailing newlines, so retain the key line and
# add the required single newline inside jq when comparing RouterOS contents.
expected_key_line="$(tr -d '\r\n' < "$public_key_file")"
key_path="$(jq -er '.container.container_config.authorized_key_path' <<<"$qdevice_desired")"

verify_authorized_key() {
  routeros_request GET "$ROUTEROS_URL/rest/file?.proplist=name,type,size,contents" |
    jq -e --arg key_path "$key_path" --arg expected_key_line "$expected_key_line" '
      (type == "array")
      and ([.[] | select(.name == $key_path)] | length == 1)
      and ([.[] | select(.name == $key_path)][0].type == "file")
      and (([.[] | select(.name == $key_path)][0].size // "0" | tonumber) > 0)
      and ([.[] | select(.name == $key_path)][0].contents == ($expected_key_line + "\n"))
    ' >/dev/null
}

# Do not start qnetd until the mounted SSH bootstrap file is exactly the
# committed public key. The later verification repeats this check after the
# container is running so a changed file cannot pass unnoticed.
if ! verify_authorized_key; then
  echo "The qdevice authorized_keys file does not match the committed public key." >&2
  exit 1
fi

if [[ "$container_status_lower" != running ]]; then
  start_payload=$(jq -cn --arg number "$container_id" '{number:$number}')
  routeros_request POST "$ROUTEROS_URL/rest/container/start" "$start_payload" >/dev/null
fi

for attempt in $(seq 1 24); do
  containers=$(routeros_request GET "$ROUTEROS_URL/rest/container")
  if ! jq -e 'type == "array"' <<<"$containers" >/dev/null; then
    echo "RouterOS returned a malformed container collection while starting qnetd." >&2
    exit 1
  fi
  container_status="$(container_runtime_status "$container_id" <<<"$containers")"
  container_status_lower="$container_status"
  if [[ "$container_status_lower" == running ]]; then
    break
  fi
  if [[ "$attempt" == 24 ]]; then
    echo "RouterOS qnetd container did not reach running state." >&2
    exit 1
  fi
  sleep 5
done

# Verify exact native objects before creating the fresh immutable plan.
if ! jq -e --argjson required "$mount_specs" '
  def canonical_native_src:
    if type == "string" and startswith("/usb1/") then .[1:] else . end;
  (type == "array")
  and (length == 3)
  and (all(.[]; type == "object" and (.list | type) == "string" and (.src | type) == "string" and (.dst | type) == "string"))
  and (map({list:.list,src:(.src | canonical_native_src),dst:.dst}) | sort_by(.list)) == ($required | sort_by(.list))
' <<<"$(routeros_request GET "$ROUTEROS_URL/rest/container/mounts")" >/dev/null; then
  echo "The recovered RouterOS mount set does not match the reviewed qnetd declaration." >&2
  exit 1
fi
if ! jq -e --argjson wanted "$container_spec" '
  def values:
    if . == null then []
    elif type == "array" then .
    elif type == "string" then split(",") | map(select(length > 0))
    else []
    end;
  def canonical_root_path:
    if type == "string" and startswith("/usb1/") then .[1:] else . end;
  def truthy:
    tostring | ascii_downcase as $value | ["true", "yes", "on", "1"] | index($value) != null;
  def runtime_state:
    if ((.status // "") | tostring | length) > 0 then
      (.status | tostring | ascii_downcase)
    elif ((.running | tostring | ascii_downcase) == "true") then
      "running"
    elif ((.running | tostring | ascii_downcase) == "false") then
      "stopped"
    elif ((.stopped | tostring | ascii_downcase) == "true") then
      "stopped"
    elif ((.stopped | tostring | ascii_downcase) == "false") then
      "running"
    else
      ""
    end;
  (type == "array")
  and (length == 1)
  and (.[0] as $actual
    | ($actual["remote-image"] // "") == $wanted["remote-image"]
      and ($actual.interface // "") == $wanted.interface
      and (($actual["root-dir"] // "") | canonical_root_path) == ($wanted["root-dir"] | canonical_root_path)
      and ($actual.name // "") == $wanted.name
      and (($actual.mountlists // []) | values | sort) == ($wanted.mountlists | sort)
      and (($actual["start-on-boot"] // false) | truthy)
      and (($actual.logging // false) | truthy)
      and ($actual.comment // "") == $wanted.comment
      and (($actual | runtime_state) == "running"))
' <<<"$(routeros_request GET "$ROUTEROS_URL/rest/container")" >/dev/null; then
  echo "The recovered RouterOS container does not match the reviewed qnetd declaration." >&2
  exit 1
fi

if ! verify_authorized_key; then
  echo "The recovered qdevice authorized_keys file changed after container start." >&2
  exit 1
fi
