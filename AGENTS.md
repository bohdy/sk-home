# AGENTS.md

## Purpose

This repository contains home network and lab automation. Agents working here must prefer clear, maintainable, well-documented changes over fast but opaque edits.

## Task Start Workflow

Before starting any new logical task:

1. Verify local `main` is up to date with `origin/main`.
2. Return to `main`.
3. Create a fresh descriptive branch from `main`.
4. Use `/compact` to reduce context usage when the environment supports it.

If `/compact` is not supported in the current environment, reduce context load manually and continue without blocking the task.

## Git Workflow

- All git commits in this repository MUST be signed.
- Agents should verify commit signing is enabled before creating commits.
- Agents should verify local `main` matches `origin/main` before branching for a new logical task.
- Every new logical task MUST begin from a new branch based on `main`.
- Branch names should be short, descriptive, and reflect the task being performed.

Future hook or CI enforcement for signed commits is encouraged, but the minimum requirement today is that agents follow the signed-commit rule for every commit they create.

## Code Standards

- All code MUST be commented.
- Comments must explain intent, assumptions, behavior, and non-obvious logic.
- Comments should not repeat what trivial syntax already makes obvious.
- When modifying existing code, update nearby comments so they remain accurate.
- Minimize hardcoded values whenever practical.
- Prefer variables, configuration, or environment-based values instead of embedding changeable values directly in code.
- Secrets MUST never be hardcoded in source files.
- When secrets or configurable values are needed, use the repository's existing variable, configuration, or secret-management mechanisms whenever possible.
- Non-secret infrastructure settings that define desired state should usually be committed as normal repository configuration.
- Do not keep real shared configuration only in `*.example` files when that configuration is intended to be the repository source of truth.
- Reserve example files for templates, onboarding, or local-secret guidance; commit actual non-sensitive defaults and shared values in real config files.

## Documentation Standards

- Documentation MUST be kept up to date whenever code, behavior, setup, usage, or repository structure changes.
- `README.md` files are important documentation and MUST be maintained.
- Updating `AGENTS.md` itself is welcomed when the repository workflow, standards, or expectations need to be adjusted.
- If a change affects setup, usage, configuration, deployment, or repository layout, update the relevant `README.md` in the same task.
- Do not leave documentation updates as implied follow-up work when the change has already been made.

## Working Rules

- Inspect the repository before making changes.
- Keep edits focused on the current task.
- Do not revert or overwrite user changes unless explicitly instructed to do so.
- Prefer maintainable solutions over clever shortcuts.
- If introducing a new configurable value, document how it is set and why it exists.

## Verification

- Verify the changed files after editing them.
- Summarize what was validated when reporting completed work.
- Call out any verification gaps or follow-up automation that would improve enforcement.
