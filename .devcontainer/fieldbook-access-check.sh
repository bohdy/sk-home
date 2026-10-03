#!/usr/bin/env bash
# Verify the mounted shared memory as the container user without reading secrets.
# This startup probe checks access only; each material turn still needs fresh main.
set -euo pipefail

fieldbook_path=/home/ubuntu/src/fieldbook
global_instructions=/home/ubuntu/.codex/AGENTS.md
probe_path=

# Always remove only the file created by this probe, including on interruption.
cleanup() {
  if [[ -n "${probe_path}" ]]; then
    rm -f -- "${probe_path}"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Identify the execution environment and give a bounded mount repair remedy.
fail() {
  printf 'Fieldbook access check failed on container %s as %s: %s\n' "$(hostname)" "$(id -un)" "$1" >&2
  printf 'Expected Fieldbook: %s; global instructions: %s\n' "${fieldbook_path}" "${global_instructions}" >&2
  printf '%s\n' 'Ensure the Dev Containers launcher HOME paths exist on the actual Docker daemon host, then rebuild/recreate the devcontainer. Do not start material work until access and fresh origin/main reads succeed.' >&2
  exit 1
}

# Reading both entrypoints proves file access, not that a running model loaded them.
for instructions in "${fieldbook_path}/AGENTS.md" "${global_instructions}"; do
  [[ -f "${instructions}" && -r "${instructions}" ]] || fail "Cannot read ${instructions}"
  cat -- "${instructions}" >/dev/null || fail "Read failed: ${instructions}"
done

# Reject an incomplete mount while avoiding network access or credential loading.
git_dir=$(git -C "${fieldbook_path}" rev-parse --absolute-git-dir) || fail 'Cannot resolve Fieldbook Git metadata'
git_common_dir=$(git -C "${fieldbook_path}" rev-parse --path-format=absolute --git-common-dir) || fail 'Cannot resolve shared Fieldbook Git metadata'
[[ -d "${git_dir}" && -r "${git_dir}" && -x "${git_dir}" ]] || fail "Cannot access Git directory: ${git_dir}"
[[ -d "${git_common_dir}" && -r "${git_common_dir}" && -x "${git_common_dir}" ]] || fail "Cannot access shared Git directory: ${git_common_dir}"

# Create one private temporary note to verify required writes; never touch notes.
notes_dir="${fieldbook_path}/docs/projects"
[[ -d "${notes_dir}" ]] || fail "Missing notes directory: ${notes_dir}"
umask 077
probe_path=$(mktemp "${notes_dir}/.codex-access-check.XXXXXXXX") || fail "Cannot create temporary note in ${notes_dir}"
printf '%s\n' 'Fieldbook access probe' >"${probe_path}" || fail 'Cannot write temporary note'
rm -- "${probe_path}" || fail 'Cannot remove temporary note'
probe_path=
printf '%s\n' 'Fieldbook instruction reads, Git metadata access and bounded note writes passed. Fetch and read current origin/main before material work.'
