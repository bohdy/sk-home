#!/usr/bin/env bash

# Reconcile only the RouterOS-native qnetd mount and container objects that
# the pinned provider cannot write on RouterOS 7.23. The caller must apply the
# reviewed provider plan before invoking this script so the state-only desired
# records and provider-managed prerequisites already exist.
set -euo pipefail

: "$MIKROTIK_USERNAME"
: "$MIKROTIK_PASSWORD"
: "$ROUTEROS_URL"
: "$STACK_PATH"

# Use curl's stdin configuration so credentials never appear in process
# arguments, logs, or repository files. Responses are piped directly to jq or
# discarded; this helper never prints a RouterOS response.
routeros_request() {
  local method="$1"
  local url="$2"
  local payload=${3-}

  REQUEST_METHOD="$method" REQUEST_URL="$url" REQUEST_PAYLOAD="$payload" \
    jq -nr '
      "user = " + (($ENV.MIKROTIK_USERNAME + ":" + $ENV.MIKROTIK_PASSWORD) | @json),
      "url = " + ($ENV.REQUEST_URL | @json),
      "request = " + ($ENV.REQUEST_METHOD | @json),
      "insecure",
      "fail",
      "silent",
      "show-error",
      "header = " + ("Content-Type: application/json" | @json),
      (if ($ENV.REQUEST_PAYLOAD // "") == "" then empty else "data = " + ($ENV.REQUEST_PAYLOAD | @json) end)
    ' | curl --config -
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
    or (($container["remote-image"] | type) != "string")
    or (($container["remote-image"] | length) == 0)
    or (($container.interface | type) != "string")
    or (($container["root-dir"] | type) != "string")
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
    or (($container.container_config | type) != "object")
    or (($container.container_config.layer_dir | type) != "string")
    or (($container.container_config.tmpdir | type) != "string")
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

qdevice_interface="$(jq -er '.interface_name' <<<"$network_spec")"
qdevice_address="$(jq -er '.address' <<<"$network_spec")"
qdevice_gateway="$(jq -er '.gateway' <<<"$network_spec")"
qdevice_vlan="$(jq -er '.vlan_id | tostring' <<<"$network_spec")"
qdevice_bridge="$(jq -er '.bridge' <<<"$network_spec")"
qdevice_frame_types="$(jq -er '.frame_types' <<<"$network_spec")"
qdevice_image="$(jq -er '."remote-image"' <<<"$container_spec")"
qdevice_layer_dir="$(jq -er '.layer_dir' <<<"$container_config_spec")"
qdevice_tmpdir="$(jq -er '.tmpdir' <<<"$container_config_spec")"

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
jq -e --arg interface "$qdevice_interface" --arg address "$qdevice_address" --arg gateway "$qdevice_gateway" '
  [.[] | select(.name == $interface)] as $matches
  | ($matches | length == 1)
    and ($matches[0].address == $address)
    and ($matches[0].gateway == $gateway)
' <<<"$veths" >/dev/null
jq -e --arg interface "$qdevice_interface" --arg bridge "$qdevice_bridge" --arg pvid "$qdevice_vlan" --arg frame_types "$qdevice_frame_types" '
  [.[] | select(.interface == $interface)] as $matches
  | ($matches | length == 1)
    and ($matches[0].bridge == $bridge)
    and (($matches[0].pvid | tostring) == $pvid)
    and ($matches[0]["frame-types"] == $frame_types)
' <<<"$ports" >/dev/null
jq -e --arg interface "$qdevice_interface" --arg bridge "$qdevice_bridge" --arg vlan "$qdevice_vlan" '
  def members($value):
    if $value == null then []
    elif ($value | type) == "array" then $value
    elif ($value | type) == "string" then ($value | split(",") | map(select(length > 0)))
    else []
    end;
  def occurrences($value; $member):
    [members($value)[] | select(. == $member)] | length;
  . as $all
  | [ $all[] | select(.bridge == $bridge and ((.["vlan-ids"] | tostring) == $vlan)) ] as $matches
  | ([ $all[] | occurrences(.untagged; $interface) ] | add // 0) as $untagged_occurrences
  | ([ $all[] | occurrences(.tagged; $interface) ] | add // 0) as $tagged_occurrences
  | ($matches | length == 1)
    and (occurrences($matches[0].untagged; $interface) == 1)
    and (occurrences($matches[0].tagged; $interface) == 0)
    and ($untagged_occurrences == 1)
    and ($tagged_occurrences == 0)
' <<<"$vlans" >/dev/null

required_paths="$(jq -ce '
  [
    .container["root-dir"],
    (.container["root-dir"] | split("/") | .[0:-1] | join("/")),
    .container.container_config.layer_dir,
    .container.container_config.tmpdir,
    (.mounts | to_entries[] | .value.src)
  ] | map(select(length > 0)) | unique
' <<<"$qdevice_desired")"
jq -e --argjson required "$required_paths" '
  all($required[]; . as $path | any($files[]; .name == $path and .type == "directory"))
' <<<"$files" >/dev/null
jq -e --arg layer_dir "$qdevice_layer_dir" --arg tmpdir "$qdevice_tmpdir" '
  (.["layer-dir"] // "") == $layer_dir and (.tmpdir // "") == $tmpdir
' <<<"$container_config" >/dev/null
jq -e '
  . as $config
  | ($config["registry-url"] // $config.registry_url // "") as $registry
  | ($config["assumed-registry-url"] // "") as $assumed
  | (["", "docker.io", "registry-1.docker.io", "https://registry-1.docker.io"] | index($registry) != null)
    and (["", "docker.io", "registry-1.docker.io"] | index($assumed) != null)
' <<<"$container_config" >/dev/null

# Existing mount rows are either absent or exactly the desired set. Any
# unrelated, duplicate, or partial row is a conflict and is never overwritten.
if ! jq -e --argjson required "$mount_specs" '
  if type != "array" then false
  elif length == 0 then true
  else
    (all(.[]; type == "object" and (.list | type) == "string" and (.src | type) == "string" and (.dst | type) == "string"))
    and (map({list:.list,src:.src,dst:.dst}) | sort_by(.list)) == ($required | sort_by(.list))
  end
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
        and ($actual["root-dir"] // "") == $wanted["root-dir"]
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
  elif [[ "$mount_count" != 1 ]] || ! jq -e --argjson wanted "$mount_spec" 'any(.[]; .list == $wanted.list and .src == $wanted.src and .dst == $wanted.dst)' <<<"$mounts" >/dev/null; then
    echo "The RouterOS mount $mount_list is conflicting or duplicated." >&2
    exit 1
  fi
done < <(jq -c '.[]' <<<"$mount_specs")

containers=$(routeros_request GET "$ROUTEROS_URL/rest/container")
if ! jq -e 'type == "array"' <<<"$containers" >/dev/null; then
  echo "RouterOS returned a malformed container collection before creation." >&2
  exit 1
fi
container_id=$(jq -r --arg image "$qdevice_image" '[.[] | select((.["remote-image"] // "") == $image)] | if length == 1 then .[0][".id"] else "" end' <<<"$containers")
if [[ -z "$container_id" ]]; then
  container_payload="$(jq -cn --argjson wanted "$container_spec" '{
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
  container_id=$(jq -r --arg image "$qdevice_image" '[.[] | select((.["remote-image"] // "") == $image)] | if length == 1 then .[0][".id"] else "" end' <<<"$containers")
  container_status=$(jq -r --arg id "$container_id" '[.[] | select(.[".id"] == $id)] | if length == 1 then (.[0].status // "") else "" end' <<<"$containers")
  if [[ -n "$container_id" ]] && [[ "$container_status" =~ ^(stopped|running)$ ]]; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    echo "RouterOS qnetd image extraction did not finish." >&2
    exit 1
  fi
  sleep 5
done

container_status_lower=$(printf '%s' "$container_status" | tr '[:upper:]' '[:lower:]')

public_key_file="terraform/$STACK_PATH/qdevice-authorized.pub"
expected_key_content="$(printf '%s\n' "$(tr -d '\r\n' < "$public_key_file")")"
key_path="$(jq -er '.container.container_config.authorized_key_path' <<<"$qdevice_desired")"

verify_authorized_key() {
  routeros_request GET "$ROUTEROS_URL/rest/file?.proplist=name,type,size,contents" |
    jq -e --arg key_path "$key_path" --arg expected_content "$expected_key_content" '
      (type == "array")
      and ([.[] | select(.name == $key_path)] | length == 1)
      and ([.[] | select(.name == $key_path)][0].type == "file")
      and (([.[] | select(.name == $key_path)][0].size // "0" | tonumber) > 0)
      and ([.[] | select(.name == $key_path)][0].contents == $expected_content)
    ' >/dev/null
}

# Do not start qnetd until the mounted SSH bootstrap file is exactly the
# committed public key. The later verification repeats this check after the
# container is running so a changed file cannot pass unnoticed.
verify_authorized_key

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
  container_status=$(jq -r --arg id "$container_id" '[.[] | select(.[".id"] == $id)] | if length == 1 then (.[0].status // "") else "" end' <<<"$containers")
  container_status_lower=$(printf '%s' "$container_status" | tr '[:upper:]' '[:lower:]')
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
jq -e --argjson required "$mount_specs" '
  (type == "array")
  and (length == 3)
  and (all(.[]; type == "object" and (.list | type) == "string" and (.src | type) == "string" and (.dst | type) == "string"))
  and (map({list:.list,src:.src,dst:.dst}) | sort_by(.list)) == ($required | sort_by(.list))
' <<<"$(routeros_request GET "$ROUTEROS_URL/rest/container/mounts")" >/dev/null
jq -e --argjson wanted "$container_spec" '
  def values:
    if . == null then []
    elif type == "array" then .
    elif type == "string" then split(",") | map(select(length > 0))
    else []
    end;
  def truthy:
    tostring | ascii_downcase as $value | ["true", "yes", "on", "1"] | index($value) != null;
  (type == "array")
  and (length == 1)
  and (.[0] as $actual
    | ($actual["remote-image"] // "") == $wanted["remote-image"]
      and ($actual.interface // "") == $wanted.interface
      and ($actual["root-dir"] // "") == $wanted["root-dir"]
      and (($actual.mountlists // []) | values | sort) == ($wanted.mountlists | sort)
      and (($actual["start-on-boot"] // false) | truthy)
      and (($actual.logging // false) | truthy)
      and ($actual.comment // "") == $wanted.comment
      and (($actual.status // "") | ascii_downcase) == "running")
' <<<"$(routeros_request GET "$ROUTEROS_URL/rest/container")" >/dev/null

verify_authorized_key
