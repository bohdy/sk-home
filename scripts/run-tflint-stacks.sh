#!/usr/bin/env bash

# Fail fast on shell errors and unset variables so the hook does not mask
# linting problems behind partial execution.
set -euo pipefail

# Resolve the repository root from the script location so the hook behaves the
# same whether pre-commit runs it from the repo root or another working path.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

# Discover Terraform stack roots dynamically so the script does not need a
# hardcoded stack list whenever a new root module is added.
all_stacks=()
while IFS= read -r stack_dir; do
  all_stacks+=("${stack_dir}")
done < <(find "${repo_root}/terraform/stacks" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "${#all_stacks[@]}" -eq 0 ]]; then
  echo "No Terraform stacks were found under terraform/stacks."
  exit 0
fi

# Stop with an actionable error when the local hook dependencies are missing
# instead of letting pre-commit fail with a less specific command-not-found.
if ! command -v tflint >/dev/null 2>&1; then
  echo "tflint is required for Terraform linting. Install it and rerun pre-commit."
  exit 1
fi

# Normalize a path relative to the repository root when possible so matching
# logic can make simple prefix checks without depending on the caller's cwd.
normalize_path() {
  local candidate="$1"

  if [[ "${candidate}" = "${repo_root}/"* ]]; then
    printf '%s\n' "${candidate#"${repo_root}/"}"
    return
  fi

  printf '%s\n' "${candidate#./}"
}

# Decide whether the changed file means linting should fan out to every stack.
# Module and shared-config changes can affect multiple roots, so linting only
# one stack would miss regressions in sibling stacks.
requires_all_stacks() {
  local path="$1"

  [[ "${path}" == terraform/modules/* ]] && return 0
  [[ "${path}" == .tflint.hcl ]] && return 0
  [[ "${path}" == .pre-commit-config.yaml ]] && return 0

  return 1
}

# Collect the exact set of stack roots affected by the incoming filenames.
selected_stack_candidates=()
run_all_stacks="false"

if [[ "$#" -eq 0 ]]; then
  run_all_stacks="true"
else
  for raw_path in "$@"; do
    path="$(normalize_path "${raw_path}")"

    if requires_all_stacks "${path}"; then
      run_all_stacks="true"
      break
    fi

    if [[ "${path}" =~ ^terraform/stacks/([^/]+)/ ]]; then
      stack_name="${BASH_REMATCH[1]}"
      selected_stack_candidates+=("${repo_root}/terraform/stacks/${stack_name}")
    fi
  done
fi

if [[ "${run_all_stacks}" == "true" ]]; then
  stack_targets=("${all_stacks[@]}")
else
  stack_targets=()
  while IFS= read -r stack_dir; do
    [[ -n "${stack_dir}" ]] || continue
    stack_targets+=("${stack_dir}")
  done < <(printf '%s\n' "${selected_stack_candidates[@]}" | sort -u)
fi

if [[ "${#stack_targets[@]}" -eq 0 ]]; then
  echo "No Terraform stack changes require TFLint."
  exit 0
fi

for stack_dir in "${stack_targets[@]}"; do
  # Lint each stack root separately so provider blocks, variables, and root
  # module structure are evaluated in the correct Terraform context.
  stack_name="${stack_dir##*/}"
  echo "Running tflint in terraform/stacks/${stack_name}"
  (
    cd "${stack_dir}"
    tflint --config="${repo_root}/.tflint.hcl"
  )
done
