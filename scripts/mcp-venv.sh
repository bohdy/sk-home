#!/usr/bin/env bash
# Create the repository-owned adapter environment from the committed lockfile.
# The lock is installed with hashes and without build isolation so local and CI
# checks use the same dependency set without a second unpinned resolver pass.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${MCP_BOOTSTRAP_PYTHON:-python3}"
venv_dir="${MCP_VENV_DIR:-${repo_root}/.venv/mcp}"
project_dir="${repo_root}/services/synology-file-station-mcp"
lock_file="${project_dir}/requirements.lock"

if [[ ! -f "${lock_file}" ]]; then
  echo "MCP dependency lockfile is missing: ${lock_file}" >&2
  exit 1
fi

if [[ ! -x "${venv_dir}/bin/python" ]]; then
  mkdir -p "$(dirname -- "${venv_dir}")"
  "${python_bin}" -m venv "${venv_dir}"
fi

venv_python="${venv_dir}/bin/python"
"${venv_python}" -m pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  --no-build-isolation \
  --require-hashes \
  --requirement "${lock_file}"

# The lockfile already supplies every runtime and build dependency. Installing
# the local project without dependency resolution keeps package metadata from
# replacing the reviewed, hash-checked set above.
"${venv_python}" -m pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  --no-build-isolation \
  --no-deps \
  "${project_dir}"

printf '%s\n' "${venv_python}"
