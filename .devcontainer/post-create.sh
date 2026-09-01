#!/usr/bin/env bash
set -euo pipefail

# Docker's --env-file parser can preserve a matching quote pair around the
# token. Normalize it before bws parses the value, and keep the same behavior
# for every interactive Bash session in the devcontainer.
normalize_bws_access_token() {
  local token="${BWS_ACCESS_TOKEN:-}"
  local first_char="${token:0:1}"
  local last_char="${token: -1}"

  # Strip only a complete matching quote pair. A dangling quote is rejected
  # instead of silently deleting a real token character and weakening the
  # fail-closed behavior of every later Bitwarden command.
  case "${first_char}" in
    '"')
      if [[ "${last_char}" != '"' ]]; then
        printf '%s\n' 'BWS_ACCESS_TOKEN has an unmatched double quote; use the unquoted Docker env-file form.' >&2
        return 1
      fi
      token="${token:1:${#token}-2}"
      ;;
    "'")
      if [[ "${last_char}" != "'" ]]; then
        printf '%s\n' 'BWS_ACCESS_TOKEN has an unmatched single quote; use the unquoted Docker env-file form.' >&2
        return 1
      fi
      token="${token:1:${#token}-2}"
      ;;
  esac

  export BWS_ACCESS_TOKEN="${token}"
}

normalize_bws_access_token

# Keep BWS authentication state out of the container filesystem while giving
# the CLI an explicit profile with the string-valued setting it expects.
BWS_CONFIG_DIR="${HOME}/.config/bws"
BWS_CONFIG_FILE="${BWS_CONFIG_DIR}/config"
mkdir -p "${BWS_CONFIG_DIR}"
if [ ! -f "${BWS_CONFIG_FILE}" ]; then
  printf '%s\n' \
    '[profiles.default]' \
    'server_base = "https://api.bitwarden.com"' \
    'server_api = "https://api.bitwarden.com"' \
    'server_identity = "https://identity.bitwarden.com"' \
    'state_opt_out = "true"' \
    > "${BWS_CONFIG_FILE}"
elif grep -Eq '^[[:space:]]*state_opt_out[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*$' "${BWS_CONFIG_FILE}"; then
  # Repair the boolean form written by older local bootstrap attempts.
  sed -i -E 's/^([[:space:]]*state_opt_out[[:space:]]*=[[:space:]]*)(true|false)([[:space:]]*)$/\1"true"\3/' "${BWS_CONFIG_FILE}"
fi

# Trust the repository-local mise configuration before installing managed tools.
mise trust

# Install the pinned toolset defined in mise.toml for this workspace.
mise install

# Verify the OpenTofu CLI is available through mise before installing hooks that
# invoke `tofu` directly.
mise exec -- tofu version

# mise-managed tools may not be on PATH yet in devcontainer lifecycle shells, so
# run pre-commit through mise's environment instead of relying on shell activation.
mise exec -- pre-commit install

# Add mise activation for future interactive bash sessions without duplicating it
# when the devcontainer lifecycle command is re-run.
MISE_ACTIVATION='eval "$(mise activate bash)"'
if ! grep -qxF "${MISE_ACTIVATION}" "${HOME}/.bashrc"; then
  printf '\n%s\n' "${MISE_ACTIVATION}" >> "${HOME}/.bashrc"
fi

# Install the normalizer once so repeated lifecycle runs do not grow .bashrc.
# Version the marker so an existing devcontainer receives the stricter
# matching-pair implementation on its next lifecycle run.
BWS_TOKEN_NORMALIZATION_MARKER='# Normalize Docker env-file quoting for BWS_ACCESS_TOKEN (strict matching).'
if ! grep -qxF "${BWS_TOKEN_NORMALIZATION_MARKER}" "${HOME}/.bashrc"; then
  printf '\n%s\n' "${BWS_TOKEN_NORMALIZATION_MARKER}" >> "${HOME}/.bashrc"
  declare -f normalize_bws_access_token >> "${HOME}/.bashrc"
  printf '%s\n' 'normalize_bws_access_token' >> "${HOME}/.bashrc"
fi
