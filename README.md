# sk-home

This repository was intentionally reset to an almost-empty learning repo.

The previous home-lab automation implementation was archived in Git before this reset:

- Archive branch: `archive-2026-04-23-pre-learning-reset`
- Archive tag: `archive-pre-learning-reset-2026-04-23`

Use those refs whenever you want to review or restore the original home-lab automation, scripts, workflows, and operational documentation.

## Current Goal

The active working tree is intentionally minimal. Keep only `README.md` and Codex-related files committed by default, then add new project files only when a specific learning task requires them.

The currently intended committed surface is:

- `README.md`
- `.gitignore`
- `AGENTS.md`
- repo-local Codex files under `.codex/`

## Rebuild Rules

- Reintroduce one concern at a time.
- Keep secrets outside the repo and load them through the shared secret-management approach when automation returns.
- Update documentation in the same task whenever behavior or layout changes.
- Keep production on `main` and publish new work through pull requests from descriptive branches.
- Do not keep placeholder project directories when they are not actively used.

## Suggested First Steps

1. Define the first learning target.
2. Add only the minimum files needed for that target.
3. Update `README.md`, `AGENTS.md`, or `.codex/` files when the task changes workflow or expectations.
4. Verify the new piece in isolation before adding the next one.
