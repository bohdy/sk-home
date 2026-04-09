#!/usr/bin/env bash

set -euo pipefail

# Resolve the repository root from the script location so CI jobs and local
# operators can call this helper from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF' >&2
Usage:
  load-bitwarden-secrets.sh [--format export|github-env] [--project-id <id>] [--ssh-dir <path>] [--kubeconfig-dir <path>] [--kubeconfig-secret-names <csv>] <profile>

Profiles:
  terraform             Export Terraform and backend credentials.
  mikrotik-certificates Export certificate workflow credentials and write SSH files.

Environment:
  BWS_ACCESS_TOKEN                Required Bitwarden Secrets Manager access token.
  BITWARDEN_PROJECT_ID            Optional default project scope when --project-id is omitted.
  MIKROTIK_ACME_STATE_DIR         Optional base directory for certificate workflow state.
  TERRAFORM_RUNTIME_STATE_DIR     Optional base directory for Terraform helper state such as kubeconfig materialization.

Examples:
  eval "$(./scripts/load-bitwarden-secrets.sh terraform)"
  eval "$(./scripts/load-bitwarden-secrets.sh mikrotik-certificates)"
  ./scripts/load-bitwarden-secrets.sh --format github-env terraform >> "${GITHUB_ENV}"
EOF
  exit 1
}

format="export"
profile=""
project_id="${BITWARDEN_PROJECT_ID:-}"
ssh_dir=""
kubeconfig_dir=""
kubeconfig_secret_names="KUBECONFIG_CONTENT"
github_env_file="${GITHUB_ENV:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      shift
      [[ $# -gt 0 ]] || usage
      format="$1"
      ;;
    --project-id)
      shift
      [[ $# -gt 0 ]] || usage
      project_id="$1"
      ;;
    --ssh-dir)
      shift
      [[ $# -gt 0 ]] || usage
      ssh_dir="$1"
      ;;
    --kubeconfig-dir)
      shift
      [[ $# -gt 0 ]] || usage
      kubeconfig_dir="$1"
      ;;
    --kubeconfig-secret-names)
      shift
      [[ $# -gt 0 ]] || usage
      kubeconfig_secret_names="$1"
      ;;
    -h|--help)
      usage
      ;;
    terraform|mikrotik-certificates)
      profile="$1"
      ;;
    *)
      echo "Unsupported argument: $1" >&2
      usage
      ;;
  esac

  shift
done

[[ -n "${profile}" ]] || usage

if [[ "${format}" != "export" && "${format}" != "github-env" ]]; then
  echo "Unsupported output format: ${format}" >&2
  exit 1
fi

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

require_secret() {
  local secret_name="$1"

  if [[ -z "${!secret_name:-}" ]]; then
    echo "Missing required Bitwarden secret: ${secret_name}" >&2
    exit 1
  fi
}

emit_mask() {
  local value="$1"
  local mask_line

  [[ -n "${value}" ]] || return 0

  # Register every non-empty line so GitHub masks both single-line values and
  # multiline material such as private keys when they accidentally appear.
  while IFS= read -r mask_line || [[ -n "${mask_line}" ]]; do
    [[ -n "${mask_line}" ]] || continue
    printf '::add-mask::%s\n' "${mask_line}"
  done <<< "${value}"
}

emit_value() {
  local key="$1"
  local value="$2"

  case "${format}" in
    export)
      # Use shell-escaped exports so callers can safely eval the output.
      printf 'export %s=%q\n' "${key}" "${value}"
      ;;
    github-env)
      [[ -n "${github_env_file}" ]] || {
        echo "GITHUB_ENV must be set when using --format github-env." >&2
        exit 1
      }

      emit_mask "${value}"

      # Use heredoc syntax so multiline secrets such as SSH materials survive
      # without truncation when appended to GITHUB_ENV.
      printf '%s<<__BITWARDEN_EOF__\n%s\n__BITWARDEN_EOF__\n' "${key}" "${value}" >> "${github_env_file}"
      ;;
  esac
}

write_file() {
  local file_path="$1"
  local file_mode="$2"
  local value="$3"

  mkdir -p "$(dirname "${file_path}")"
  printf '%s\n' "${value}" > "${file_path}"
  chmod "${file_mode}" "${file_path}"
}

emit_optional_value() {
  local secret_name="$1"
  local target_name="$2"

  if [[ -n "${!secret_name:-}" ]]; then
    emit_value "${target_name}" "${!secret_name}"
  fi
}

resolve_first_present_secret() {
  local secret_names_csv="$1"
  local secret_name=""
  local secret_value=""
  local -a secret_candidates=()
  local prefer_k3s="false"

  IFS=',' read -r -a secret_candidates <<< "${secret_names_csv}"
  for secret_name in "${secret_candidates[@]}"; do
    # Trim surrounding whitespace so callers can format the CSV for readability.
    secret_name="${secret_name#"${secret_name%%[![:space:]]*}"}"
    secret_name="${secret_name%"${secret_name##*[![:space:]]}"}"
    [[ -n "${secret_name}" ]] || continue

    if [[ ! "${secret_name}" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      echo "Invalid kubeconfig secret name: ${secret_name}" >&2
      exit 1
    fi

    secret_value="${!secret_name:-}"
    if [[ -n "${secret_value}" ]]; then
      printf '%s\n' "${secret_value}"
      return 0
    fi
  done

  # Fall back to kubeconfig content autodiscovery so operators do not need to
  # rename Bitwarden keys when migrating between cluster naming conventions.
  if [[ "${secret_names_csv}" == *"K3S"* ]]; then
    prefer_k3s="true"
  fi

  discover_kubeconfig_secret "${prefer_k3s}"

  return 0
}

looks_like_kubeconfig_content() {
  local value="$1"

  [[ "${value}" == *"apiVersion:"* ]] || return 1
  [[ "${value}" == *"clusters:"* ]] || return 1
  [[ "${value}" == *"contexts:"* ]] || return 1
  [[ "${value}" == *"users:"* ]] || return 1
  return 0
}

discover_kubeconfig_secret() {
  local prefer_k3s="$1"
  local env_name=""
  local env_value=""
  local -a env_names=()

  mapfile -t env_names < <(compgen -A variable | sort)

  # Prefer explicit cluster-tagged keys first when the caller indicates that a
  # stack should target k3s kubeconfig material.
  if [[ "${prefer_k3s}" == "true" ]]; then
    for env_name in "${env_names[@]}"; do
      [[ "${env_name}" == *"KUBECONFIG"* || "${env_name}" == *"KUBE_CONFIG"* ]] || continue
      [[ "${env_name}" == *"K3S"* ]] || continue
      env_value="${!env_name:-}"
      if looks_like_kubeconfig_content "${env_value}"; then
        printf '%s\n' "${env_value}"
        return 0
      fi
    done
  fi

  # For non-k3s stacks, prefer keys that explicitly reference the existing
  # primary/home cluster before trying generic kubeconfig secret names.
  if [[ "${prefer_k3s}" != "true" ]]; then
    for env_name in "${env_names[@]}"; do
      [[ "${env_name}" == *"KUBECONFIG"* || "${env_name}" == *"KUBE_CONFIG"* ]] || continue
      [[ "${env_name}" == *"HOME"* || "${env_name}" == *"PRIMARY"* || "${env_name}" == *"DEFAULT"* || "${env_name}" == *"LEGACY"* ]] || continue
      env_value="${!env_name:-}"
      if looks_like_kubeconfig_content "${env_value}"; then
        printf '%s\n' "${env_value}"
        return 0
      fi
    done
  fi

  # Finally, use any kubeconfig-shaped value emitted by Bitwarden.
  for env_name in "${env_names[@]}"; do
    [[ "${env_name}" == *"KUBECONFIG"* || "${env_name}" == *"KUBE_CONFIG"* ]] || continue
    env_value="${!env_name:-}"
    if looks_like_kubeconfig_content "${env_value}"; then
      printf '%s\n' "${env_value}"
      return 0
    fi
  done
}

materialize_kubeconfig() {
  local runtime_state_dir
  local resolved_kubeconfig_dir
  local kubeconfig_file
  local kubeconfig_content

  # Support multiple candidate secret names so CI can choose between kubeconfig
  # materials for legacy and k3s-managed clusters without duplicating loaders.
  kubeconfig_content="$(resolve_first_present_secret "${kubeconfig_secret_names}")"
  if [[ -z "${kubeconfig_content}" ]]; then
    return 0
  fi

  runtime_state_dir="${TERRAFORM_RUNTIME_STATE_DIR:-${REPO_ROOT}/.tmp/terraform-runtime}"
  resolved_kubeconfig_dir="${kubeconfig_dir:-${runtime_state_dir}/kubeconfig}"
  kubeconfig_file="${resolved_kubeconfig_dir}/config"

  write_file "${kubeconfig_file}" 600 "${kubeconfig_content}"
  chmod 700 "${resolved_kubeconfig_dir}"

  emit_value "TF_VAR_kubeconfig_path" "${kubeconfig_file}"
}

load_secrets_into_environment() {
  local temp_env_file
  local bws_args=(secret list --output env)

  if [[ -n "${project_id}" ]]; then
    bws_args=(secret list "${project_id}" --output env)
  fi

  temp_env_file="$(mktemp)"

  # Let the Bitwarden CLI render shell-compatible KEY=VALUE lines so the helper
  # can consume multiline secret values without custom parsing.
  bws "${bws_args[@]}" > "${temp_env_file}"

  set -a
  # shellcheck disable=SC1090
  source "${temp_env_file}"
  set +a

  rm -f "${temp_env_file}"
}

emit_terraform_profile() {
  require_secret "AWS_ACCESS_KEY_ID"
  require_secret "AWS_SECRET_ACCESS_KEY"
  require_secret "MIKROTIK_USERNAME"
  require_secret "MIKROTIK_PASSWORD"

  emit_value "AWS_ACCESS_KEY_ID" "${AWS_ACCESS_KEY_ID}"
  emit_value "AWS_SECRET_ACCESS_KEY" "${AWS_SECRET_ACCESS_KEY}"
  emit_value "TF_VAR_mikrotik_username" "${MIKROTIK_USERNAME}"
  emit_value "TF_VAR_mikrotik_password" "${MIKROTIK_PASSWORD}"
  emit_optional_value "CLOUDFLARE_API_TOKEN" "TF_VAR_cloudflare_api_token"
  emit_optional_value "CLOUDFLARE_ACCOUNT_ID" "TF_VAR_cloudflare_account_id"
  emit_optional_value "PROXMOX_VE_ENDPOINT" "TF_VAR_proxmox_endpoint"
  emit_optional_value "PROXMOX_VE_API_TOKEN" "TF_VAR_proxmox_api_token"
  emit_optional_value "PROXMOX_SSH_PRIVATE_KEY" "TF_VAR_proxmox_ssh_private_key"
  emit_optional_value "K8S_TOKEN" "TF_VAR_k8s_token"
  emit_optional_value "SSH_PUB_KEY" "TF_VAR_bohdy_ssh_public_key"
  emit_optional_value "DOCKER_USERNAME" "TF_VAR_docker_username"
  emit_optional_value "DOCKER_PASSWORD" "TF_VAR_docker_password"
  emit_optional_value "DOCKER_AUTH_BASE64" "TF_VAR_docker_auth_base64"
  emit_optional_value "TAILSCALE_AUTHKEY" "TF_VAR_tailscale_authkey"
  emit_optional_value "K3S_TOKEN" "TF_VAR_k3s_token"
  emit_optional_value "MONGO_ROOT_PASSWORD" "TF_VAR_mongo_root_password"
  emit_optional_value "UNPOLLER_USERNAME" "TF_VAR_unpoller_username"
  emit_optional_value "UNPOLLER_PASSWORD" "TF_VAR_unpoller_password"
  materialize_kubeconfig
  emit_optional_telegram_values
}

emit_optional_telegram_values() {
  # Keep Telegram notification settings optional in the shared loader so local
  # Terraform commands and unrelated workflows do not break before operators
  # finish provisioning the new Bitwarden values.
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    emit_value "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN}"
  fi

  if [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    emit_value "TELEGRAM_CHAT_ID" "${TELEGRAM_CHAT_ID}"
  fi

  if [[ -n "${TELEGRAM_MESSAGE_THREAD_ID:-}" ]]; then
    emit_value "TELEGRAM_MESSAGE_THREAD_ID" "${TELEGRAM_MESSAGE_THREAD_ID}"
  fi
}

emit_mikrotik_certificates_profile() {
  local acme_state_dir
  local resolved_ssh_dir
  local ssh_key_file
  local known_hosts_file

  require_secret "CLOUDFLARE_API_TOKEN"
  require_secret "MIKROTIK_USERNAME"
  require_secret "MIKROTIK_SSH_PRIVATE_KEY"
  require_secret "MIKROTIK_SSH_KNOWN_HOSTS"

  acme_state_dir="${MIKROTIK_ACME_STATE_DIR:-${REPO_ROOT}/.tmp/mikrotik-acme}"
  resolved_ssh_dir="${ssh_dir:-${acme_state_dir}/ssh}"
  ssh_key_file="${resolved_ssh_dir}/id_ed25519"
  known_hosts_file="${resolved_ssh_dir}/known_hosts"

  # Materialize SSH credentials into files because the renewal script and the
  # OpenSSH client both operate on paths rather than raw environment values.
  write_file "${ssh_key_file}" 600 "${MIKROTIK_SSH_PRIVATE_KEY}"
  write_file "${known_hosts_file}" 600 "${MIKROTIK_SSH_KNOWN_HOSTS}"
  chmod 700 "${resolved_ssh_dir}"

  emit_value "CLOUDFLARE_API_TOKEN" "${CLOUDFLARE_API_TOKEN}"
  emit_value "MIKROTIK_SSH_USERNAME" "${MIKROTIK_USERNAME}"
  emit_value "MIKROTIK_SSH_PRIVATE_KEY_FILE" "${ssh_key_file}"
  emit_value "MIKROTIK_SSH_KNOWN_HOSTS_FILE" "${known_hosts_file}"
  emit_optional_telegram_values
}

require_command "bws"

if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
  echo "Set BWS_ACCESS_TOKEN before loading Bitwarden Secrets Manager values." >&2
  exit 1
fi

load_secrets_into_environment

case "${profile}" in
  terraform)
    emit_terraform_profile
    ;;
  mikrotik-certificates)
    emit_mikrotik_certificates_profile
    ;;
esac
