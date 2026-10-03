# Synology File Station MCP runtime

This child is an independent, suspended Flux workload. It starts one non-root tunnel-client PID 1 and one read-only Synology File Station MCP child per Deployment, with no Kubernetes Service, ingress, persistent volume, or VIP. The image is staged as `activation-required`; activation requires a trusted GHCR digest, valid `nas.bohdal.name` certificate chain, a successful dedicated non-admin Media identity preflight, and the external Secret bootstrap.

The adapter exposes only bounded listing, name search, metadata, text/document reading, image/PDF preview, and media metadata tools. It resolves the File Station virtual share through the documented `list_share` API and accepts it only when the returned `additional.real_path` is exactly `/volume1/Media`. Every item must return a segment-safe `additional.real_path` beneath that root; mount/link types, traversal, absolute caller paths, encoded separators, redirects, and invalid sessions are rejected. Search tasks are stopped and cleaned up in every outcome.

The external bootstrap contract is a Secret named `mcp-synology-credentials` with `control-plane-api-key`, `synology-username`, and `synology-password`, plus a non-secret `control-plane-tunnel-id` key in the ConfigMap. The runtime key is limited to Control Plane Read and Use. The separate TLS renewal work must complete before this child can be activated; do not bypass certificate verification or add a second NAS origin.

Rollback scales the Deployment to zero or deletes the workload and revokes its runtime key; suspending Flux alone does not stop an already-running process. Activation must include a safe File Station write-permission denial check for the dedicated identity, without creating or mutating a Media file.
