#!/usr/bin/env bash
# Preserve OpenTofu's three outcomes without uploading empty or failed plans.
set -euo pipefail
set +e
tofu -chdir="terraform/${STACK_PATH}" plan -input=false -detailed-exitcode -out=tofuplan
code=$?
set -e
echo "exitcode=${code}" >> "$GITHUB_OUTPUT"
if [[ "$code" == 0 ]]; then
  node -e 'require("node:fs").rmSync(`terraform/${process.env.STACK_PATH}/tofuplan`,{force:true})'
fi
if [[ "$code" != 0 && "$code" != 2 ]]; then exit 1; fi
