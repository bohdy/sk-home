#!/usr/bin/env bash
set -euo pipefail

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
