# Pin the Ubuntu LTS release so a moving `latest` tag cannot invalidate APT
# indexes halfway through a reproducible devcontainer build.
FROM ubuntu:24.04

ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*
RUN install -dm 755 /etc/apt/keyrings
# Use Mise's current official repository. The previous mise.en.dev endpoint is
# blocked by the configured DNS resolver, which prevents a TLS-verified build.
# Convert the ASCII-armored signing key to APT's required binary keyring format.
RUN curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor --output /etc/apt/keyrings/mise-archive-keyring.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg] https://mise.jdx.dev/deb stable main" | tee /etc/apt/sources.list.d/mise.list

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    unzip \
    git \
    openssh-client \
    gnupg \
    software-properties-common \
    curl \
    sudo \
    npm \
    mise \
    jq \
    python3-yaml \
    ripgrep \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install the official CNPG kubectl plugin from a pinned release. Keep each
# architecture and checksum pair together and reject unsupported builders so a
# mismatched or moving artifact cannot enter the development image.
RUN set -eu; \
    case "${TARGETARCH:-}" in \
        amd64) \
            cnpg_arch="linux_x86_64"; \
            cnpg_sha256="12a54d93c1fcf6b3b37deba5cd2c5c6fe4fbd2029dc5cb1f7c02d5e93fa14838"; \
            ;; \
        arm64) \
            cnpg_arch="linux_arm64"; \
            cnpg_sha256="232f6b65a94637a4c81d3a6471bfce5de3bd3750e5c9fe6af27b80f84bb3a719"; \
            ;; \
        *) \
            echo "Unsupported TARGETARCH=${TARGETARCH:-}" >&2; \
            exit 1; \
            ;; \
    esac; \
    cnpg_deb="/tmp/kubectl-cnpg_1.30.1_${cnpg_arch}.deb"; \
    trap 'rm -f "${cnpg_deb}"' EXIT; \
    curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
        "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.30.1/kubectl-cnpg_1.30.1_${cnpg_arch}.deb" \
        --output "${cnpg_deb}"; \
    printf '%s  %s\n' "${cnpg_sha256}" "${cnpg_deb}" | sha256sum --check --status -; \
    dpkg --install "${cnpg_deb}"

# Keep the container user stable across Ubuntu base image changes. Some Ubuntu
# images include this user and others do not, so create it only when needed.
RUN id -u ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ubuntu

# Allow devcontainer features and local workflow tests to perform root-owned
# setup from the non-root workspace user.
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

RUN curl https://bws.bitwarden.com/install | sh

# Install act so GitHub Actions workflows can be exercised from inside the devcontainer.
RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

USER ubuntu
