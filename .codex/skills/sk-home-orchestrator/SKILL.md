---
name: sk-home-orchestrator
description: Coordinate planner, coder, firewall, review, and documentation subagents for scoped sk-home repository changes. Use for implementation or infrastructure tasks, not broad research or external administration.
---

# Sk-home orchestrator

Use this skill to run a bounded, evidence-based implementation workflow in this repository. The orchestrator owns task state, Git operations, validation, pull requests, and any workflow dispatch. Role agents work only in their assigned phase and report through their thread. They never commit, push, merge, dispatch an apply, or retrieve secrets.

## Start and scope

Accept a scoped repository implementation, configuration, or documentation task. Decline broad research and external administration. Read `AGENTS.md`, the relevant repository documentation, and applicable local skills before delegating.

Before any repository work, start or enter the devcontainer. All inspection, edits, Git operations, agent orchestration, tests, formatting, and validation must run inside it. If a required tool is missing, add it to `.devcontainer` or `mise.toml`, rebuild or reopen the devcontainer, and retry there. Then fetch and verify `origin/main`, fast-forward local `main` to that exact commit, and create the task branch directly from `origin/main`. Preserve unrelated working-tree changes. MUST use GitHub MCP for GitHub state and operations. MUST use Context7 MCP for documentation and external technical documentation. Stop and report a blocker if either required MCP dependency or its required documentation cannot be verified. Use a fresh, sequential subagent thread for each role in the shared checkout. Do not run two writers at once.

Classify a task as infrastructure work when it changes OpenTofu, Kubernetes manifests, GitHub Actions, managed-device configuration, routing, DNS, load balancing, firewall policy, or network policy. Record the classification and why.

## Task sizing and agent budget

Classify the task before delegating and use the smallest workflow that can meet its acceptance criteria. Start with the lightest class supported by the task and escalate if its scope or risk changes.

### Light

Use for reversible, low-impact work such as typo fixes, comments, one- or two-line documentation or policy changes, model-assignment changes, formatting, and focused read-only diagnosis. It must not change infrastructure, deployment behavior, security controls, or external systems.

- The orchestrator performs inspection, edits, and validation itself.
- Do not start planner, firewaller, documenter, or final reviewer subagents.
- Start at most one reviewer when the user requests independent review. Start exactly one reviewer when the change touches a security-sensitive instruction.
- Use zero automatic coder repair cycles. If the reviewer blocks, the root agent may make one focused correction and rerun that reviewer, but must not publish an unreviewed fix. If the reviewer blocks again, stop or escalate to standard.

### Standard

Use for multi-file code or documentation changes that do not affect infrastructure, security controls, deployment, or external systems.

- Run planner, coder, and reviewer in sequence.
- Run documenter only when the change alters user-facing documentation or system behavior that needs a separate documentation pass.
- Skip firewaller.
- Allow one repair cycle.

### Infrastructure and security

Use for OpenTofu, Kubernetes, GitHub Actions, managed-device, routing, DNS, load-balancing, firewall, network-policy, credential, authentication, deployment, or external-system changes.

- Run planner, coder, firewaller, reviewer, documenter, and final reviewer. The firewaller is mandatory and must report either proposed rule changes or an explicit no-change result.
- Require the existing live prerequisites and production gates.
- Allow up to three repair cycles.

Escalate when a light or standard task becomes infrastructure, security, deployment, or external-system work, changes more files than expected, or gains a destructive side effect. Roles that are optional for the selected class are skipped and the reason is recorded. The orchestrator may use a stricter class, but must not use a lighter class for infrastructure, security, deployment, or external-system work.

## Delivery flow

1. Select the task class and agent budget above before delegating.
2. For light work, perform the implementation and validation in the root thread, then run the optional single reviewer or the mandatory security-sensitive reviewer with [reviewer instructions](references/reviewer.md).
3. For standard work, run the planner with [planner instructions](references/planner.md), the coder with [coder instructions](references/coder.md), and the reviewer with [reviewer instructions](references/reviewer.md) in sequence. Add the documenter with [documenter instructions](references/documenter.md) only when the task requires a separate documentation pass.
4. For infrastructure, security, deployment, or external-system work, run the planner, coder, firewaller with [firewaller instructions](references/firewaller.md), reviewer, documenter, and final reviewer. The reviewer must consider the firewaller report, including its explicit no-change result.
5. The initial implementation review does not consume a repair cycle. For light work, the root agent may make one focused correction and rerun the same reviewer; a second block stops the task or escalates it to standard. For standard and full-risk work, send exact findings to a new coder thread and repeat all affected reviews within the selected class budget. On the first unresolved result beyond that budget, stop and present the findings without publishing or deploying.
6. Run the repository-defined checks that apply to the final diff, inspect the diff for secrets, and prepare a draft pull request according to `AGENTS.md`.

Keep raw reports in the role threads. The pull request and tracked documentation may contain only concise, sanitized findings, validation results, risks, and decisions.

## Infrastructure dispatch

The skill may prepare production deployment, but it must not bypass the repository's controls. After the pull request is merged, start a separate deployment phase from the merged `main` commit. Verify the commit, required checks, applicable firewaller and reviewer approvals, and the immutable plan from the trusted `main` workflow.

Show the user the sanitized deployment evidence and ask for explicit in-chat approval before dispatching an existing production workflow. Never merge a pull request, bypass a GitHub `production` environment approval, create an ad hoc apply path, or apply a different plan than the reviewed immutable artifact. Stop if the evidence is stale, incomplete, destructive, or inconsistent with the merged change.

## Completion record

Report the task classification, agents run, repair-cycle count, changed files, validation results, firewall status, PR status, and any deployment approval still required. State verification gaps plainly.
