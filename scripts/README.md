# Scripts Notes

This directory is reserved for future helper scripts.

Add scripts only when they support a specific learning task, and keep each script small, commented, and safe to inspect.

The current scaffold includes [`repo_checks.py`](repo_checks.py) as the repo-native entrypoint behind `make format`, `make lint`, and `make validate`. Extend that script or replace its implementation behind the same commands when the repository grows more specialized tooling.

Before adding secret-aware automation, document:

- what inputs the script expects
- which values are secrets
- how those secrets are injected without being echoed or committed
- what failure mode is safer than partial execution
