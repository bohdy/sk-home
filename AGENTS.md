# AGENTS.md

## Purpose

This repository is now an almost-empty learning repo. Agents working here must prefer clear, maintainable, well-documented changes over fast but opaque edits. This repository also targets a high security standard. Agents must treat credential handling, secret exposure, and log safety as first-class concerns in every task.

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
- Exposing secrets in logs, CI output, artifacts, comments, or other observable channels is a major failure and must be treated as a severe regression.
- When secrets or configurable values are needed, use the repository's existing variable, configuration, or secret-management mechanisms whenever possible.
- Bitwarden Secrets Manager is the shared source of truth for repository secrets in both local runs and GitHub Actions unless a newer documented mechanism replaces it.
- When introducing or modifying secret-handling automation, agents must prefer designs that preserve masking, minimize plaintext exposure, and fail closed when masking or secure injection cannot be guaranteed.
- Non-secret infrastructure settings that define desired state should usually be committed as normal repository configuration.
- Do not keep real shared configuration only in `*.example` files when that configuration is intended to be the repository source of truth.
- Reserve example files for templates, onboarding, or local-secret guidance; commit actual non-sensitive defaults and shared values in real config files.
- New functions, features, workflows, and dependencies MUST use the latest stable versions available when they are introduced. Upgrades to existing components must be evaluated and planned carefully instead of being changed automatically.
- Rebuild the repository in small steps. Prefer one clearly scoped learning change per task instead of restoring large operational batches.
- Keep the default committed surface minimal. Unless a task requires more, keep only `README.md`, `.gitignore`, and Codex-related files such as `AGENTS.md` and `.codex/`.

## Documentation Standards

- Documentation MUST be kept up to date whenever code, behavior, setup, usage, or repository structure changes.
- `README.md` files are important documentation and MUST be maintained.
- `AGENTS.md` is important repository policy and MUST be updated whenever workflow, standards, tooling expectations, or agent instructions change.
- In Markdown prose and list items, keep one physical line per paragraph or list item instead of manual hard-wraps. Preserve multi-line layout only where Markdown syntax requires it, such as code blocks, tables, or other structured content.
- If a change affects setup, usage, configuration, deployment, or repository layout, update the relevant `README.md` in the same task.
- If a change affects repository workflow, documentation policy, secret handling, automation conventions, or agent expectations, update `AGENTS.md` in the same task.
- Do not leave documentation updates as implied follow-up work when the change has already been made.

## Working Rules

- Inspect the repository before making changes.
- Keep edits focused on the current task.
- Prefer smaller, reviewable patches over oversized batch edits when changing code or documentation.
- Do not revert or overwrite user changes unless explicitly instructed to do so.
- Prefer maintainable solutions over clever shortcuts.
- If introducing a new configurable value, document how it is set and why it exists.
- The archive refs named in `README.md` are the source of truth for the pre-reset implementation. Do not copy large chunks back into the active tree without first scoping the specific learning goal.
- Remove placeholder directories and helper files when they are no longer actively serving the current learning task.

## Repo Skills

- Repo-local Codex skills live under `.codex/skills/`.
- Mention repo-local skills in `AGENTS.md` when they materially affect repository workflow, tooling expectations, or agent behavior.
- Keep `AGENTS.md` at the policy and discoverability level; detailed procedures belong in the skill itself.
- Keep repo-local skills aligned with the current repository workflow whenever they are added or changed.

## Pull Request Workflow

- `main` is the production branch.
- New work should be published through pull requests that target `main`.
- Do not keep feature work on `main`; create or move it onto a descriptive branch before pushing.
- When creating pull requests, prefer a draft PR by default unless the user explicitly asks for ready review.
- Before creating or updating a pull request, run all repo-defined formatting, linting, and validation steps that apply to the changed code and stop if any of them fail.
- Do not create or update a pull request when the repo does not yet define the required checks for the changed code; add or document those checks first.
- Pull request bodies must include a short summary plus a longer description that covers every changed file or logical change area.

## Verification

- Verify the changed files after editing them.
- When changing tracked Markdown, shell scripts, or GitHub Actions workflows, verify the matching repo-hygiene checks still pass or explicitly call out why they could not be run locally.
- For any change that touches credentials, authentication, CI injection, or secret-management paths, explicitly verify that secrets are not exposed in logs or other observable outputs.
- Summarize what was validated when reporting completed work.
- Call out any verification gaps or follow-up automation that would improve enforcement.
