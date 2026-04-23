# sk-home

This repository was intentionally reset to a minimal learning scaffold.

The previous home-lab automation implementation was archived in Git before this reset:

- Archive branch: `archive-2026-04-23-pre-learning-reset`
- Archive tag: `archive-pre-learning-reset-2026-04-23`

Use those refs whenever you want to review or restore the original Terraform stacks, scripts, workflows, and operational documentation.

## Current Goal

The active working tree is now optimized for rebuilding the lab from scratch in small, understandable steps.

The repository keeps only a few documented placeholders:

- [`terraform/README.md`](terraform/README.md) for future infrastructure notes and stack conventions
- [`scripts/README.md`](scripts/README.md) for future helper scripts
- [`config/README.md`](config/README.md) for future non-secret committed configuration

## Rebuild Rules

- Reintroduce one concern at a time.
- Prefer committed non-secret desired state over undocumented local setup.
- Keep secrets outside the repo and load them through the shared secret-management approach when automation returns.
- Update documentation in the same task whenever behavior or layout changes.

## Suggested First Steps

1. Define the first learning target, such as one Terraform stack, one script, or one CI workflow.
2. Add only the minimum files needed for that target.
3. Document the intent, inputs, and safety assumptions next to the new code.
4. Verify the new piece in isolation before adding the next one.
