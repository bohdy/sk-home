# Terraform Notes

This directory is intentionally minimal after the repository reset.

Add new Terraform work here only when you have a clearly scoped learning goal.

Recommended approach:

1. Start with one small stack root.
2. Keep provider and backend assumptions documented in that stack.
3. Commit only non-secret desired state.
4. Keep credentials outside the repository and avoid logging them during local runs or CI.

When Terraform returns to this repo, keep the directory structure simple and split stacks by operational blast radius rather than accumulating unrelated concerns into one root.
