#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  require-runner-tools.sh <tool> [<tool> ...]

Examples:
  ./scripts/require-runner-tools.sh bash git node unzip
  ./scripts/require-runner-tools.sh bash bws curl openssl ssh scp nc
EOF
  exit 1
}

[[ "$#" -gt 0 ]] || usage

# Check each requested tool independently so workflow logs point to the exact
# missing prerequisite instead of failing later inside a larger automation step.
for required_tool in "$@"; do
  if ! command -v "${required_tool}" >/dev/null 2>&1; then
    echo "Missing required tool: ${required_tool}" >&2
    exit 1
  fi
done
