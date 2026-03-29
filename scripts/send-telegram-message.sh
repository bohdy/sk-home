#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  send-telegram-message.sh [--message-file <path>]

Environment:
  TELEGRAM_BOT_TOKEN              Required Telegram bot token.
  TELEGRAM_CHAT_ID                Required Telegram chat identifier.
  TELEGRAM_MESSAGE_THREAD_ID      Optional Telegram forum topic/thread identifier.

Examples:
  printf 'Hello from GitHub Actions\n' | ./scripts/send-telegram-message.sh
  ./scripts/send-telegram-message.sh --message-file /tmp/message.txt
EOF
  exit 1
}

message_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message-file)
      shift
      [[ $# -gt 0 ]] || usage
      message_file="$1"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unsupported argument: $1" >&2
      usage
      ;;
  esac

  shift
done

emit_mask() {
  local value="$1"
  local mask_line

  [[ -n "${value}" ]] || return 0
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] || return 0

  # Register every non-empty line so bot tokens and identifiers stay masked
  # even if a later debugging change accidentally writes them to workflow logs.
  while IFS= read -r mask_line || [[ -n "${mask_line}" ]]; do
    [[ -n "${mask_line}" ]] || continue
    printf '::add-mask::%s\n' "${mask_line}"
  done <<< "${value}"
}

require_env() {
  local variable_name="$1"

  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required environment variable: ${variable_name}" >&2
    exit 1
  fi
}

build_message() {
  local raw_message

  if [[ -n "${message_file}" ]]; then
    [[ -f "${message_file}" ]] || {
      echo "Message file does not exist: ${message_file}" >&2
      exit 1
    }
    raw_message="$(cat "${message_file}")"
  else
    raw_message="$(cat)"
  fi

  # Refuse empty notifications so workflows do not emit vague or misleading
  # messages when an earlier step forgets to populate its message body.
  if [[ -z "${raw_message}" ]]; then
    echo "Telegram message body cannot be empty." >&2
    exit 1
  fi

  printf '%s' "${raw_message}"
}

require_env "TELEGRAM_BOT_TOKEN"
require_env "TELEGRAM_CHAT_ID"

emit_mask "${TELEGRAM_BOT_TOKEN}"
emit_mask "${TELEGRAM_CHAT_ID}"
emit_mask "${TELEGRAM_MESSAGE_THREAD_ID:-}"

telegram_message="$(build_message)"
telegram_api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
curl_args=(
  --silent
  --show-error
  --fail
  --retry 3
  --retry-delay 2
  --max-time 20
  --request POST
  --url "${telegram_api_url}"
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}"
  --data-urlencode "text=${telegram_message}"
)

# Route messages to a specific forum topic only when the caller provides a
# thread identifier. Leaving it unset preserves compatibility with normal chats.
if [[ -n "${TELEGRAM_MESSAGE_THREAD_ID:-}" ]]; then
  curl_args+=(--data-urlencode "message_thread_id=${TELEGRAM_MESSAGE_THREAD_ID}")
fi

curl "${curl_args[@]}" >/dev/null
