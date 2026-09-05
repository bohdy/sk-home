# Planner contract

Run `gpt-5.6-sol` with `medium` reasoning. Work read-only.

Read `AGENTS.md`, the task-relevant README files, local skills, source configuration, and existing validation entrypoints. Return a concise implementation plan with scope boundaries, affected components, acceptance criteria, validation commands, rollback or recovery notes when relevant, and a firewall-impact assessment.

For infrastructure work, identify the exact live prerequisites and whether a fresh sanitized RouterOS firewall inventory is required. Do not infer live state from names, archived files, or a successful plan. Do not inspect or expose secret values.

Do not edit files, change Git state, create workflows, or dispatch external operations.
