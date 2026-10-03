# Grafana MCP runtime image

This image contains Grafana MCP server `v2.0.0` and OpenAI tunnel-client runtime `v0.0.15`. The Dockerfile selects the official Linux `x86_64` or `arm64` release archives and verifies the release SHA-256 values before extracting the two binaries.

The verified archive digests are `mcp-grafana_Linux_x86_64.tar.gz` `0a0dde2c882c24fedcce79a07d97b232f71730c744b84a09b6b0735c2ca3d024`, `mcp-grafana_Linux_arm64.tar.gz` `5b29581cad5ce21a0db67c655e5e7e71a9163b4e1ba1b518559baa3c54133a28`, `tunnel-client-runtime-v0.0.15-linux-amd64.zip` `f26f8b3ee6c335e38fa5cfbe6ce5635f53738f08a26eecf07d6cebacab4a1abf`, and `tunnel-client-runtime-v0.0.15-linux-arm64.zip` `a868d295385b22449341fa141b911f3e991583e45b1fa2a5bfb946aed1861b88`.

Builds must be performed by the trusted image workflow from `main`, with the resulting registry digest reviewed before the Flux child is unsuspended. Kubernetes uses `/usr/local/bin/tunnel-client` as PID 1 and its declarative config starts exactly one Grafana MCP process over stdio.
