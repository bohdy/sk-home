# sk-home

This repository was intentionally reset to an almost-empty learning repo.

The previous home-lab automation implementation was archived in Git before this reset:

- Archive branch: `archive-2026-04-23-pre-learning-reset`
- Archive tag: `archive-pre-learning-reset-2026-04-23`

Use those refs whenever you want to review or restore the original home-lab automation, scripts, workflows, and operational documentation.

## Current Goal

The active working tree is intentionally minimal. Keep only `README.md` and Codex-related files committed by default, then add new project files only when a specific learning task requires them.

The currently intended committed surface is:

- `README.md`
- `.gitignore`
- `AGENTS.md`
- repo-local Codex files under `.codex/`

## Rebuild Rules

- Reintroduce one concern at a time.
- Keep secrets outside the repo and load them through the shared secret-management approach when automation returns.
- Update documentation in the same task whenever behavior or layout changes.
- Keep production on `main` and publish new work through pull requests from descriptive branches.
- Do not keep placeholder project directories when they are not actively used.

## Local Development

### Prerequisites

- [act](https://github.com/nektos/act) - Run GitHub Actions locally
- Docker - Required by act
- Bitwarden account with access to repository secrets

### Environment Setup

1. Create a `.env` file in the repository root with your Bitwarden access token:
   ```bash
   BWS_ACCESS_TOKEN="your_bitwarden_access_token_here"
   ```

2. Get your Bitwarden access token from: Account Settings → Security → API Key

### Testing Workflows Locally

To test GitHub Actions workflows locally using act:

```bash
# Load environment variables and run Terraform workflow
source .env && act --workflows .github/workflows/terraform.yaml \
  -P self-hosted=node:18-bookworm \
  --container-architecture linux/amd64 \
  --secret BWS_ACCESS_TOKEN="$BWS_ACCESS_TOKEN"
```

**Important notes:**
- Uses `node:18-bookworm` Docker image (required for Bitwarden action compatibility)
- Secrets are retrieved from Bitwarden using the access token
- This ensures local testing matches CI/CD behavior exactly

### Troubleshooting

- **OpenSSL errors**: Ensure you're using `node:18-bookworm` (not `node:18-bullseye`)
- **Access token errors**: Verify your Bitwarden access token is valid and has proper permissions
- **Docker issues**: Make sure Docker is running and you have sufficient permissions
