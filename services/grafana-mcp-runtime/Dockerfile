# This image combines the verified Grafana MCP release with the verified
# OpenAI tunnel-client runtime. Python is used only for the standard-library
# stdio policy relay; the staged Kubernetes workload remains suspended until
# the operator records the final image digest and credentials.
FROM python:3.14.8-slim-trixie@sha256:89fb7d3da20043c370643435258bdd7ab755d326d359001d02988ed15ae5219e

# Consume BuildKit automatic target architecture for native and multi-platform release selection.
ARG TARGETARCH
ARG GRAFANA_VERSION=v2.0.0
ARG TUNNEL_VERSION=v0.0.15

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install --no-install-recommends --yes bash ca-certificates curl unzip tar \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) grafana_arch=x86_64; grafana_sha=0a0dde2c882c24fedcce79a07d97b232f71730c744b84a09b6b0735c2ca3d024; tunnel_arch=amd64; tunnel_sha=f26f8b3ee6c335e38fa5cfbe6ce5635f53738f08a26eecf07d6cebacab4a1abf ;; \
      arm64) grafana_arch=arm64; grafana_sha=5b29581cad5ce21a0db67c655e5e7e71a9163b4e1ba1b518559baa3c54133a28; tunnel_arch=arm64; tunnel_sha=a868d295385b22449341fa141b911f3e991583e45b1fa2a5bfb946aed1861b88 ;; \
      *) echo "unsupported target architecture" >&2; exit 1 ;; \
    esac; \
    grafana_archive="mcp-grafana_Linux_${grafana_arch}.tar.gz"; \
    tunnel_platform=${tunnel_arch}; \
    tunnel_archive="tunnel-client-runtime-${TUNNEL_VERSION}-linux-${tunnel_platform}.zip"; \
    grafana_base="https://github.com/grafana/mcp-grafana/releases/download/${GRAFANA_VERSION}"; \
    tunnel_base="https://github.com/openai/tunnel-client/releases/download/${TUNNEL_VERSION}"; \
    curl --fail --location --proto '=https' --tlsv1.2 --output "/tmp/${grafana_archive}" "${grafana_base}/${grafana_archive}"; \
    curl --fail --location --proto '=https' --tlsv1.2 --output "/tmp/${tunnel_archive}" "${tunnel_base}/${tunnel_archive}"; \
    echo "${grafana_sha}  /tmp/${grafana_archive}" | sha256sum --check --strict; \
    echo "${tunnel_sha}  /tmp/${tunnel_archive}" | sha256sum --check --strict; \
    tar --extract --file "/tmp/${grafana_archive}" --directory /tmp; \
    install -D --mode=0755 "/tmp/mcp-grafana" /usr/local/bin/mcp-grafana; \
    unzip -p "/tmp/${tunnel_archive}" tunnel-client-runtime > /usr/local/bin/tunnel-client; \
    chmod 0755 /usr/local/bin/tunnel-client; \
    rm -rf /tmp/*

# Keep the official release binary unchanged and place the policy relay beside
# it. The relay has no third-party runtime dependency.
COPY grafana_mcp_guard.py /usr/local/bin/grafana-mcp-guard.py
RUN chmod 0755 /usr/local/bin/grafana-mcp-guard.py

# The workload never needs root. Kubernetes also enforces a read-only root
# filesystem and a RuntimeDefault seccomp profile at the pod boundary.
RUN useradd --system --uid 65532 --home-dir /nonexistent --shell /usr/sbin/nologin mcp \
    && install --directory --owner=65532 --group=65532 --mode=0750 /run/tunnel-client /tmp/mcp \
    && chown 65532:65532 /usr/local/bin/mcp-grafana /usr/local/bin/tunnel-client

USER 65532:65532
WORKDIR /tmp/mcp
ENTRYPOINT ["/usr/local/bin/tunnel-client"]
