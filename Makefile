# Keep the repo-native PR checks behind stable entrypoints so skills and docs
# can refer to one command surface even as the underlying implementation grows.
PYTHON ?= python3
CHECKS := $(PYTHON) scripts/repo_checks.py

.PHONY: format lint validate

format:
	$(CHECKS) format

lint:
	$(CHECKS) lint

validate:
	$(CHECKS) validate
