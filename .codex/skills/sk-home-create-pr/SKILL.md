---
name: sk-home-create-pr
description: Create pull requests for the sk-home repository using the repo's required workflow. Use when Codex needs to move work off main if needed, reformat changed code, run all repo-defined lint and validation checks for the changed code, prepare signed commits, push a branch, and open a GitHub pull request into main with a short summary and a detailed walkthrough that covers every changed file or logical change area.
---

# Sk Home Create Pr

## Overview

Use this skill to publish `sk-home` changes through a pull request without bypassing the repository workflow.

Treat `main` as the production branch. Open pull requests into `main` and avoid pushing feature work directly to it.

## Workflow

1. Inspect the repo state before changing anything.
2. Ensure the work lives on a non-`main` branch.
3. Discover the formatter, linter, and validation commands that apply to the changed code.
4. Reformat the changed code.
5. Run all relevant lint and validation checks and stop if any fail.
6. Verify signed-commit behavior before creating commits.
7. Update `AGENTS.md` and `README.md` when the change affects workflow, repository behavior, setup, usage, configuration, or repo layout.
8. Review the diff against the current remote `main` commit reported by GitHub MCP and write a complete pull request walkthrough.
9. Commit intentionally if there are uncommitted changes.
10. Publish the exact reviewed branch commit through GitHub MCP when supported, otherwise use local Git; either operation may run outside the devcontainer.
11. Open or update a pull request into `main` through GitHub MCP when supported, using `gh` only as a documented last resort.

## Inspect State

Start by checking:

- `git status --short --branch`
- current branch name
- whether local `main` matches the current remote `main` commit reported by GitHub MCP when a new branch still needs to be created, using local Git to synchronize it when needed
- whether `git config --get commit.gpgsign` is enabled
- which files changed against the current remote `main` commit reported by GitHub MCP

Read `AGENTS.md` and follow its current workflow rules if they changed since the skill was written.

## Branch Rules

If the work is already on a non-`main` branch, keep using that branch unless the user explicitly asks to rename or replace it.

If the current branch is `main`:

- If there are no working tree changes, use GitHub MCP to verify the current remote `main` commit, use local Git to fetch and confirm that exact commit, then fast-forward local `main` and create a fresh descriptive branch from it.
- If there are local changes or local commits that should become a PR, create a fresh descriptive branch at the current `HEAD` before committing or pushing. Do not leave feature work on `main`.

Keep branch names short and descriptive.

## Documentation Sync

Do not treat documentation updates as optional follow-up work.

When the PR changes repository workflow, automation conventions, agent expectations, setup, usage, configuration, deployment, or repository layout, update the relevant docs in the same branch before opening the PR.

At minimum, check whether these files need changes:

- `AGENTS.md` for workflow, policy, or agent-expectation changes
- `README.md` for setup, usage, configuration, behavior, or repository-layout changes

If the code change affects one of these areas and the docs were not updated, stop and fix the documentation before creating or updating the PR.

## Quality Gates

Before creating or updating a pull request, identify the repo-defined commands that apply to the changed code.

Use committed repo entrypoints when they exist, such as project scripts, `Makefile` targets, `pre-commit`, language-native task runners, or documented commands in the repo.

Apply this order:

1. run the relevant formatter or formatter wrapper for the changed code
2. run all relevant lint checks for the changed code
3. run all relevant validation or test commands for the changed code

Do not create or update the pull request until every applicable formatter, linter, and validation step passes.

If the repo does not define the required checks for the changed code yet, stop and tell the user that the missing repo-native checks must be added or specified first. Do not guess commands from file extensions or installed tools.

If a check fails, stop before creating the PR. Report the failing command and keep the branch ready for fixes instead of publishing a partially validated PR.

## Commit Rules

All commits created by this skill must be signed.

Before committing:

- stage only the intended files
- inspect the staged diff
- write a specific commit message
- use `git commit -S`

If signing is disabled, enable the repo-compliant flow before proceeding or stop and tell the user what is missing.

## Pull Request Content

Review the diff against the current remote `main` commit reported by GitHub MCP and derive the PR content from the actual change, not from assumptions. Use the local commit only after confirming that exact remote baseline is available locally.

The PR body must explain all changed code in the PR. Cover every changed file or every logical change area when several files implement one coherent change. Do not leave changed areas undocumented in the PR body.

Use this structure unless the user asks for another format:

- Title: short, specific, and consistent with the change
- Body:
  - `## Summary`
  - `## Description`
  - `## Validation`
  - `## Risks` when there are real residual risks

Prefer a draft pull request by default. Only open a ready-for-review PR when the user explicitly asks for that or the context clearly indicates it is ready.

`## Summary` should be a short description of the PR.

`## Description` should be the longer walkthrough. List each changed file or grouped change area and explain what changed and why.

`## Validation` must list every formatter, linter, and validation command that actually ran. If the workflow was blocked, do not create the PR.

## Target and Publishing Rules

Open PRs from the feature branch into `main`.

Do not push directly to `main` as part of this workflow.

Prefer GitHub MCP for remote branch, ref, commit, push, and pull request operations. These MCP calls may run outside the devcontainer. Use local Git when it is needed to publish the exact signed commit, and avoid `gh` when MCP provides the same capability. Use `gh` only as a documented last resort, never raw API calls, and stop rather than reconstructing an unsigned or unverified commit if the exact reviewed tree or required signature cannot be published and verified.

## Safety Checks

Before publishing:

- confirm no secrets or `.tmp/` artifacts are staged
- confirm the branch is not `main`
- confirm the PR target is `main`
- confirm GitHub MCP verified the published commit's tree against the locally reviewed tree and verified the required commit signature
- confirm the PR summary and description match the actual diff
- confirm the PR body covers every changed file or logical change area
- confirm all required formatting, linting, and validation steps passed
- confirm `AGENTS.md` and `README.md` were updated when the change required documentation updates

If the branch already has an open PR, update that PR instead of creating a duplicate unless the user asks for a second PR.
