# AGENTS.md

## Purpose

This repository contains home network and lab automation. Agents working here must prefer clear, maintainable, well-documented changes over fast but opaque edits. This repository also targets a high security standard. Agents must treat credential handling, secret exposure, and log safety as first-class concerns in every task.

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
- For Terraform, prefer separate stack roots when a concern can be managed independently with separate state.
- For Terraform-managed infrastructure, prefer per-device stack roots when the operational blast radius maps cleanly to one live device.
- Nested stack roots are acceptable when they keep a broader domain organized, such as `terraform/stacks/network-core/dhcp`.
- Do not let `network-core` become a catch-all Terraform root for adjacent concerns that can live in their own stack.

## Verification

- Verify the changed files after editing them.
- For any change that touches credentials, authentication, CI injection, or secret-management paths, explicitly verify that secrets are not exposed in logs or other observable outputs.
- Summarize what was validated when reporting completed work.
- Call out any verification gaps or follow-up automation that would improve enforcement.
