---
name: sk-home-write-comments
description: Write or improve comments in the sk-home repository. Use when the user explicitly asks to add, review, refresh, or improve code comments in source files, Terraform, scripts, workflows, or related config while keeping comments accurate, security-aware, and aligned with repo documentation rules.
---

# Sk Home Write Comments

## Overview

Use this skill when comment quality is the task, not as a blanket rule for every edit.

This repository requires comments to explain intent, assumptions, behavior, and non-obvious logic. Do not add comments that only narrate syntax the code already makes obvious.

Treat security and secret handling as first-class concerns. Comments must never reveal secrets, encourage plaintext handling, or normalize unsafe logging.

## Workflow

1. Read the relevant files and nearby comments before editing.
2. Identify comments that are missing, stale, misleading, or too obvious to justify keeping.
3. Update comments together with the code they describe so behavior and documentation stay in sync.
4. Prefer a small number of high-signal comments over dense line-by-line narration.
5. Re-read the edited file to confirm every retained comment is still true.

## Comment Rules

- Explain why a block exists, what assumption it depends on, or what behavior is easy to miss.
- Document security-sensitive behavior explicitly when the code touches credentials, auth, CI injection, secret loading, masking, or logging boundaries.
- Call out important invariants, ordering requirements, failure modes, and external system expectations when they are not obvious from names alone.
- Use comments to explain Terraform intent, infrastructure relationships, and non-obvious variable or provider behavior when configuration would otherwise be hard to review safely.
- Remove or rewrite comments that merely restate assignments, resource names, or simple control flow.
- Keep comments specific to the current code. Avoid generic advice that could drift out of date.

## Editing Guidance

- Match the surrounding file style for comment syntax and tone.
- Keep comments close to the code or configuration they describe.
- When a public function, module, or config section has non-obvious inputs, outputs, or side effects, add a concise comment that makes review easier.
- If a refactor changes behavior, update nearby comments in the same edit. Do not leave stale comments behind.
- If a section is self-explanatory after cleanup, prefer deleting the old comment over rewriting it.

## Documentation Sync

When comment-related work changes repository workflow, comment conventions, or agent expectations, update `AGENTS.md` in the same task.

When comment-related work changes setup, usage, configuration, or repository structure, update `README.md` in the same task.

Keep `AGENTS.md` at the policy level. Put detailed operational guidance in this skill instead of expanding repo policy text.
