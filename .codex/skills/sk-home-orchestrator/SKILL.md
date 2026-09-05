---
name: sk-home-orchestrator
description: Coordinate planner, coder, firewall, review, and documentation subagents for scoped sk-home repository changes. Use for implementation or infrastructure tasks, not broad research or external administration.
---

# Sk-home orchestrator

Use this skill to run a bounded, evidence-based implementation workflow in this repository. The orchestrator owns task state, local Git preparation, validation, remote GitHub MCP operations, pull requests, and any workflow dispatch. Role agents work only in their assigned phase and report through their thread. They never commit, push, merge, dispatch an apply, or retrieve secrets.

## Start and scope

Accept a scoped repository implementation, configuration, or documentation task. Decline broad research and external administration. Read `AGENTS.md`, the relevant repository documentation, and applicable local skills before delegating.

Before any repository work, start or enter the devcontainer. All app/code inspection, edits, Git preparation, agent orchestration, tests, formatting, and validation must run inside it. Remote GitHub operations are the exception: branch, ref, commit, push, pull request, review, issue, and workflow actions MUST use GitHub MCP and may run outside the devcontainer. Do not replace those MCP calls with shell `git`, GitHub CLI, or raw API calls. If a required app or validation tool is missing, add it to `.devcontainer` or `mise.toml`, rebuild or reopen the devcontainer, and retry there. Use GitHub MCP to verify the current remote `main` commit, then compare the local checkout with that exact commit inside the devcontainer. If the commit is not already available locally, stop because the available MCP integration cannot synchronize Git objects into the checkout. Create the task branch directly from the verified commit and preserve unrelated working-tree changes. If MCP cannot publish the exact reviewed tree and required signed commit, stop instead of reconstructing an unsigned or unverified commit. MUST use GitHub MCP for GitHub state and operations. MUST use Context7 MCP for documentation and external technical documentation. Stop and report a blocker if either required MCP dependency or its required documentation cannot be verified. Use a fresh, sequential subagent thread for each role in the shared checkout. Do not run two writers at once.

Classify a task as infrastructure work when it changes OpenTofu, Kubernetes manifests, GitHub Actions, managed-device configuration, routing, DNS, load balancing, firewall policy, or network policy. Record the classification and why.

## Inventory-first planning

The repository has no single active file named `network-inventory`. Its authoritative gateway network inventory is the existing pair `terraform/network/gw/interfaces/interfaces.auto.tfvars` and `terraform/network/gw/interfaces/vlans.auto.tfvars`: the first defines managed physical interfaces and the second defines VLAN topology, gateway addresses, and interface-list membership. The planner MUST read both files before creating or updating any plan, including a plan for a non-infrastructure change. When the task concerns DHCP scopes, leases, reservations, or address allocation, it MUST also read `terraform/network/gw/dhcp/dhcp.auto.tfvars`.

The planner must use the inventory facts in its plan by naming the affected inventory entries, interfaces, VLANs, subnets, or reservations and by calling out conflicts or missing entries. It must not substitute archived `terraform/stacks/network-core` files, uncommitted files, generated artifacts, or guessed values for the current inventory. A live RouterOS inventory artifact is a separate prerequisite for changes whose correctness depends on current device state.

## Delivery flow

1. Run the planner with [planner instructions](references/planner.md).
2. Run the coder with [coder instructions](references/coder.md), using the accepted plan.
3. For infrastructure work, run the firewaller with [firewaller instructions](references/firewaller.md). Otherwise record a reasoned skip.
4. Run the reviewer with [reviewer instructions](references/reviewer.md). It must consider the firewaller report when one exists.
5. If either review blocks the change, send the exact findings to a new coder thread and repeat the affected reviews. Allow at most three repair cycles. On the fourth unresolved result, stop and present the findings without publishing or deploying.
6. After implementation review passes, run the documenter with [documenter instructions](references/documenter.md).
7. Run a final reviewer pass over the complete diff, including documentation. Resolve its blocking findings within the same three-cycle budget.
8. Run the repository-defined checks that apply to the final diff, inspect the diff for secrets, and publish the exact reviewed commit through GitHub MCP according to `AGENTS.md`.
9. Use GitHub MCP to verify that the published commit's tree matches the locally reviewed tree and that its required signature verifies before opening or updating the pull request.

Keep raw reports in the role threads. The pull request and tracked documentation may contain only concise, sanitized findings, validation results, risks, and decisions.

## Infrastructure dispatch

The skill may prepare production deployment, but it must not bypass the repository's controls. After the pull request is merged, start a separate deployment phase from the merged `main` commit. Verify the commit, required checks, applicable firewaller and reviewer approvals, and the immutable plan from the trusted `main` workflow.

Show the user the sanitized deployment evidence and ask for explicit in-chat approval before dispatching an existing production workflow. Never merge a pull request, bypass a GitHub `production` environment approval, create an ad hoc apply path, or apply a different plan than the reviewed immutable artifact. Stop if the evidence is stale, incomplete, destructive, or inconsistent with the merged change.

## Completion record

Report the task classification, agents run, repair-cycle count, changed files, validation results, firewall status, PR status, and any deployment approval still required. State verification gaps plainly.
