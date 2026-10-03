# Synology File Station MCP runtime

This child is an independent Flux workload in namespace `mcp-synology`. Its staged state is `suspend: true`, Deployment `replicas: 0`, image `ghcr.io/bohdy/sk-home-mcp-synology:activation-required`, and ConfigMap tunnel ID `activation-required`. It has no Service, ingress, persistent volume, or VIP, runs one non-root tunnel-client PID 1 with one stdio adapter, disables the Kubernetes service-account token, and allows Cilium egress only to cluster DNS, the OpenAI control plane, and the pinned NAS HTTPS endpoint at TCP/5001.

The adapter accepts only `https://nas.bohdal.name:5001` with certificate verification enabled and uses `SYNOLOGY_REAL_ROOT=/volume1/Media` and `SYNOLOGY_SHARE_NAME=Media`. The File Station `list_share` response must identify the selected share through `data.shares[].additional.real_path=/volume1/Media`; a directory listing cannot substitute for this proof. Every `data.files[]` item used later must carry a segment-safe `additional.real_path` under that root. Traversal, absolute or encoded paths, empty segments, links, mounts, redirects, remapped roots, invalid sessions, and out-of-root metadata fail closed.

The eight exposed read-only tools are `list_entries`, `search_by_name`, `stat`, `read_text`, `read_document`, `preview_image`, `preview_pdf_page`, and `media_info`. `list_entries` and `search_by_name` default to 100 entries per page; `search_by_name` has a 20-second deadline and cleans up its asynchronous task on success, error, timeout, or cancellation. `read_text` is capped at 1MiB, `read_document` accepts PDF/DOCX/XLSX/PPTX up to 25MiB, `preview_image` accepts 25MiB and 40,000,000 decoded pixels, and `preview_pdf_page` uses the document, page, pixel, and 2MiB response limits. `media_info` downloads at most 8MiB for small supported media; larger files require self-consistent HTTP `206 Content-Range` responses and share a cumulative 64MiB range budget. Unsupported formats, playlist/concat inputs, failed probes, or unverified range behavior return basic metadata with `inspection_limited=true` and a specific limitation instead of a full download.

The runtime settings are:

| Environment setting | Default or requirement |
| --- | --- |
| `SYNOLOGY_ORIGIN` | `https://nas.bohdal.name:5001`, exact value enforced. |
| `SYNOLOGY_REAL_ROOT` | `/volume1/Media`, exact value enforced. |
| `SYNOLOGY_SHARE_NAME` | `Media`. |
| `SYNOLOGY_USERNAME` and `SYNOLOGY_PASSWORD` | Required Secret values for a dedicated non-administrator read-only File Station identity. |
| `SYNOLOGY_PAGE_SIZE` | `100`. |
| `SYNOLOGY_TEXT_BYTES` | `1MiB`. |
| `SYNOLOGY_DOCUMENT_BYTES` and `SYNOLOGY_IMAGE_BYTES` | `25MiB` each. |
| `SYNOLOGY_MEDIA_PROBE_BYTES` and `SYNOLOGY_MEDIA_SMALL_BYTES` | `64MiB` cumulative ranges and `8MiB` complete small-media download. |
| `SYNOLOGY_OUTPUT_BYTES` | `2MiB`. |
| `SYNOLOGY_ARCHIVE_MEMBERS` and `SYNOLOGY_ARCHIVE_EXPANDED_BYTES` | `512` members and `100MiB` declared expansion. |
| `SYNOLOGY_PDF_PAGES` and `SYNOLOGY_IMAGE_PIXELS` | `32` pages and `40,000,000` pixels. |
| `SYNOLOGY_TEMP_DISK_BYTES` | `100MiB`. |
| `CONTROL_PLANE_API_KEY` | Required Secret key `control-plane-api-key`; runtime Read and Use only. |
| `CONTROL_PLANE_TUNNEL_ID` | Required ConfigMap key `control-plane-tunnel-id`; actual identity is set only during reviewed activation. |
| `DO_NOT_TRACK` | `1`. |

The external Secret contract is `mcp-synology-credentials` with key metadata `control-plane-api-key`, `synology-username`, and `synology-password`; the ConfigMap `mcp-synology-config` carries non-secret `control-plane-tunnel-id`. Credential bootstrap is an operator contract, not tested Secret-provisioning automation here, so no values, account IDs, tunnel IDs, passwords, or inline plaintext Secret commands belong in Git or logs. The dedicated NAS identity must prove write denial without creating or mutating a Media file. The runtime tunnel identity must be associated with both Codex and ChatGPT in the intended organization/workspace; account-level tunnel management and association use the separately authorized `Manage` surface, while this workload key remains limited to Read and Use. The account rights, identity, and client bindings are currently unverified.

Activation uses two reviewed GitOps phases. First, review and unsuspend only this Flux child while keeping `replicas: 0`; Flux then creates the restricted, prune-protected namespace, tokenless ServiceAccount, ConfigMap, Deployment, and Cilium policy without starting the adapter. Never create the namespace imperatively to bypass its suspended owner. Second, bootstrap the approved Secret metadata through Bitwarden, replace the staged image with the trusted immutable GHCR digest, set the actual tunnel ID, repair and verify the canonical NAS certificate, and collect the dedicated identity and Media-root evidence. A separate explicit production approval is required before changing this Deployment to one replica. The certificate-renewal task owns the NAS TLS repair; do not disable verification or add another origin.

Run the following checks as separate invocations in the repository devcontainer:

```bash
mise run mcp-bootstrap
mise run mcp-lint
mise run mcp-test
mise run mcp-manifest-check
mise run mcp-container-build
mise run mcp-grafana-check
mise exec -- pre-commit run ruff-check --all-files
mise exec -- pre-commit run ruff-format --all-files
```

Use `scripts/mcp-preflight.sh --static` for credential-free manifest and staged-boundary validation. Use `scripts/mcp-preflight.sh --live synology` only against a live kubeconfig; it checks Ready nodes, Cilium and DNS Flux readiness, Secret key names, canonical NAS HTTPS, the immutable image digest, and the non-placeholder tunnel ID, then returns `exit 3` because effective NAS write/read permissions, root and link behavior, fresh Cilium/DNS/RouterOS return-path evidence, management BGP, strict certificate provenance, and both client associations remain unverified. This live preflight is incomplete infrastructure metadata, not activation acceptance. Acceptance requires fresh provenance-bearing checks for the pod DNS and return paths, Cilium policy, RouterOS and management BGP state, canonical TLS, Secret key names, complete read-only tool discovery, Media real-root/link checks, NAS write denial, and representative text, PDF/DOCX/XLSX/PPTX, image, audio, and video reads through both client bindings.

For an active incident, scale `mcp-synology` to zero or delete its Deployment, revoke its runtime key, and then suspend the Flux child; suspending Flux alone does not stop an already-running process. Reconcile the emergency scale/delete, image, tunnel ID, and suspension into Git before resuming so Flux does not recreate the workload with stale activation state. Routine changes should be reviewed GitOps changes and allowed to reconcile without an ad-hoc restart.
