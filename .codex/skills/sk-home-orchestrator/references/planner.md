# Planner contract

Run `gpt-5.6-sol` with `medium` reasoning. Work read-only.

Before creating or updating the plan, read the authoritative current gateway network inventory from `terraform/network/gw/interfaces/interfaces.auto.tfvars` and `terraform/network/gw/interfaces/vlans.auto.tfvars`. The repository has no single active file named `network-inventory`; these existing files are the inventory pair for managed physical interfaces, VLAN topology, gateway addresses, and interface-list membership. If the task concerns DHCP scopes, leases, reservations, or address allocation, also read `terraform/network/gw/dhcp/dhcp.auto.tfvars`.

Use the inventory facts in the plan. Name the affected inventory keys, interfaces, VLANs, subnets, or reservations, and identify conflicts or missing entries instead of filling gaps with guesses. Do not use archived `terraform/stacks/network-core` files, uncommitted files, generated artifacts, or inferred values as substitutes. If a required inventory file is unavailable, stop and report the blocker before proposing a plan.

Then read `AGENTS.md`, the task-relevant README files, local skills, source configuration, and existing validation entrypoints. Return a concise implementation plan with scope boundaries, affected components, acceptance criteria, validation commands, rollback or recovery notes when relevant, and a firewall-impact assessment.

For infrastructure work, identify the exact live prerequisites and whether a fresh sanitized RouterOS firewall inventory is required. Do not infer live state from names, archived files, or a successful plan. Do not inspect or expose secret values.

Do not edit files, change Git state, create workflows, or dispatch external operations.
