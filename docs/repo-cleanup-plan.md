# Repository Cleanup Plan

## Status

This plan records the cleanup audit performed on 2026-08-07 and the follow-up work that remains after the documentation and hygiene pass on branch `repo-cleanup-audit`.

- The active repository is the source of truth for current OpenTofu, Kubernetes, workflow, tooling, and operations documentation.
- No live infrastructure mutation, OpenTofu apply, state migration, or credential inspection was performed for this cleanup.
- Existing uncommitted work in `README.md`, `.devcontainer/devcontainer-lock.json`, `.opencode/`, `ops/`, and `scripts/gha-runner-cleanup.sh` was left untouched.

## Completed In This Pass

- Reconciled `README.md` and `AGENTS.md` with the active repository instead of the historical minimal-reset state.
- Updated OpenTofu, DNS, DHCP, Flow, Cloudflare Tunnel, and rollout documentation that still described completed work as future work or used the old transport path.
- Added explicit `contents: read` permissions to the DNS validation workflow.
- Removed an empty Terraform file and obsolete commented Terraform alternatives.
- Corrected a CI comment that incorrectly described floating mise-managed tools as pinned.

## Prioritized Follow-Up

### P0: Harden Terraform Workflow

The OpenTofu workflow currently retrieves Bitwarden values for pull-request plans and uploads binary plan artifacts. Separate secretless pull-request validation from trusted, production-gated plans and applies. Keep credentials unavailable to untrusted code, and retain plan artifacts only where an approved apply path requires them.

Acceptance criteria:

- Pull-request validation does not request or inject infrastructure credentials.
- Production applies consume an immutable plan created in a trusted workflow context.
- Binary plans containing sensitive values are not retained as ordinary pull-request artifacts.
- Fork pull requests receive useful validation rather than failing because secrets are unavailable.
- Secret values and raw infrastructure data remain absent from logs, summaries, and artifacts.

### P1: Complete State-Migration Cleanup

Inspect the live OpenTofu state and run read-only no-change plans before removing migration scaffolding. The Cloudflare stack still contains `import` blocks and import-only data sources, and the Proxmox observability stack still contains a `removed` block and provider workaround comments.

Acceptance criteria:

- Every imported address is confirmed present at its final managed address.
- Removing each temporary block produces no unexpected create, destroy, or replacement action.
- The cleanup is applied through the normal reviewed workflow and verified with a follow-up no-change plan.
- Migration scaffolding is removed in the same logical task rather than left in the desired-state configuration.

### P1: Make Provider Lockfiles Intentional

Decide whether each active OpenTofu stack should commit its `.terraform.lock.hcl`, then generate and review lockfiles in the repository devcontainer. The current global ignore rule and partial lockfile coverage make provider selection inconsistent across stacks.

Acceptance criteria:

- Every active stack has an explicit, reviewed provider-lockfile policy.
- Provider hashes cover the CI runner platforms that the repository supports.
- Generated `.terraform/` directories and binary plans remain ignored.

### P2: Remove Dead Workflow Plumbing

The `detect-changes` job in `.github/workflows/terraform.yaml` currently has no outputs and its consuming condition is commented out. Confirm branch-protection requirements, then either remove the no-op job or implement real change detection without reducing required validation.

Acceptance criteria:

- Every workflow job has a real dependency or documented branch-protection purpose.
- Stack planning behavior is explicit for pushes, pull requests, and manual dispatches.
- Required checks retain stable names or are deliberately migrated with repository settings.

### P2: Expand Repository Validation

Align CI with the active repository contract. Consider rendering all active Kustomize trees, checking generated SNMP output against its generator input, adding Markdown hygiene checks, and adding a rendered-secret scan that cannot emit credential values.

Acceptance criteria:

- Generated artifacts fail validation when stale.
- Active Kubernetes trees render successfully in CI without requiring infrastructure credentials.
- Validation failures identify the owning source file and remediation command.
- Secret checks fail closed without printing matched content.

### P2: Resolve CoreDNS Dashboard Coverage

The DNS dashboard contains CoreDNS queries, but the committed scrape configuration does not currently provide a dedicated CoreDNS metrics Service or scrape resource. Either wire the intended metrics path and validate live samples or remove the unsupported panels.

Acceptance criteria:

- Every retained CoreDNS dashboard panel has a validated scrape source and query.
- Empty results caused by an intentionally disabled collector are documented explicitly.
- The chosen path does not expose DNS query contents or unbounded client-controlled cardinality.

### P3: Finish Historical Documentation Review

Review remaining recovery and acceptance documents for intentional historical snapshots versus current operator procedures. In particular, distinguish the accepted UniFi cutover from disaster-recovery instructions and retain dated acceptance evidence without presenting it as pending work.

Acceptance criteria:

- Current procedures are clearly labeled and executable against the active topology.
- Historical evidence remains dated and is not mistaken for current state.
- Recovery instructions do not direct operators to run obsolete cutover or deletion steps casually.

## Constraints

- Do not read `.env` or expose any local credential values.
- Do not mutate live infrastructure directly; use OpenTofu or Flux ownership paths.
- Do not remove retained volumes, state, or generated artifacts without explicit ownership and rollback review.
- Preserve unrelated user worktree changes.

## Validation Already Run

- `SKIP=dns-check pre-commit run --all-files` passed.
- `python3 scripts/render-dns.py --check` passed.
- DNS, Flow, GeoIP, and observability Kustomize renders passed.
- `sh -n kubernetes/flux/observability/flow-geoip/geoip-refresh.sh` and the Flow dashboard JSON check passed.
- `tofu fmt -recursive -check -diff` passed.
- `git diff --check` passed.

The normal DNS pre-commit hook could not locate `mise` on the host; its underlying render and Kustomize commands passed directly.
