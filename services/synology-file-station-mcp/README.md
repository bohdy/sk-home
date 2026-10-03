# Synology File Station MCP adapter

This adapter is a bounded, read-only MCP facade over one Synology File Station share. It uses the official File Station API shape: `SYNO.FileStation.List` `list_share` discovers shares through `data.shares[]`, while `getinfo` returns `data.files[]` and metadata under `additional`. A directory listing is not accepted as a share-root proof. The adapter accepts the configured `Media` share only when the selected share reports `additional.real_path=/volume1/Media`, and every returned item must provide a segment-safe `additional.real_path` below that real root.

The adapter exposes exactly eight tools:

| Tool | Bounded behavior |
| --- | --- |
| `list_entries` | Lists a page of verified entries; default page size is 100 and caller paths are relative to the verified share. |
| `search_by_name` | Runs a recursive File Station search with a 20-second deadline and attempts both stop and clean cleanup requests in a finalizer. |
| `stat` | Returns verified metadata without downloading file content. |
| `read_text` | Reads UTF-8 text up to the configured 1MiB default and caps the encoded response. |
| `read_document` | Converts PDF, DOCX, XLSX, or PPTX input up to the 25MiB default into bounded Markdown in an isolated parser worker. |
| `preview_image` | Decodes an image up to the 25MiB default, caps it at 40,000,000 pixels, and returns a native PNG image payload. |
| `preview_pdf_page` | Renders one requested PDF page from a bounded document, with the same page and pixel limits as the parser worker. |
| `media_info` | Returns metadata and optional allowlisted `ffprobe` details without exposing tags or raw paths; large files use verified ranges. |

The source defaults and deployment contract are:

| Setting | Default or requirement | Meaning |
| --- | --- | --- |
| `SYNOLOGY_ORIGIN` | `https://nas.bohdal.name:5001` and this exact HTTPS origin is required | Sole NAS origin; redirects, proxy environment variables, alternate hosts, and disabled TLS verification are rejected. |
| `SYNOLOGY_REAL_ROOT` | `/volume1/Media` and this exact real root is required | Backend path boundary checked against File Station `additional.real_path`. |
| `SYNOLOGY_SHARE_NAME` | `Media` | Share selected by `list_share` before any caller path is accepted. |
| `SYNOLOGY_USERNAME` | Required Secret value | Dedicated non-administrator File Station principal. |
| `SYNOLOGY_PASSWORD` | Required Secret value | Password for the dedicated principal; held only in the process environment and in-memory client. |
| `SYNOLOGY_PAGE_SIZE` | `100` | Maximum default listing/search page size; callers cannot exceed the configured value. |
| `SYNOLOGY_TEXT_BYTES` | `1MiB` | Download and UTF-8 response ceiling for `read_text`. |
| `SYNOLOGY_DOCUMENT_BYTES` | `25MiB` | Download ceiling for documents and PDF page previews. |
| `SYNOLOGY_IMAGE_BYTES` | `25MiB` | Download ceiling for image previews. |
| `SYNOLOGY_MEDIA_PROBE_BYTES` | `64MiB` | Cumulative range-transfer ceiling for large `media_info` probes. |
| `SYNOLOGY_MEDIA_SMALL_BYTES` | `8MiB` | Maximum complete download for small media probes. |
| `SYNOLOGY_OUTPUT_BYTES` | `2MiB` | Encoded JSON/text/image result ceiling. |
| `SYNOLOGY_ARCHIVE_MEMBERS` | `512` | Maximum ZIP members inspected before Office conversion. |
| `SYNOLOGY_ARCHIVE_EXPANDED_BYTES` | `100MiB` | Maximum declared ZIP expansion. |
| `SYNOLOGY_PDF_PAGES` | `32` | Maximum PDF pages accepted by conversion or page rendering. |
| `SYNOLOGY_IMAGE_PIXELS` | `40,000,000` | Maximum decoded or rendered pixels. |
| `SYNOLOGY_TEMP_DISK_BYTES` | `100MiB` | Parser scratch and file-size ceiling. |
| `CONTROL_PLANE_API_KEY` | Required Secret key `control-plane-api-key` | Tunnel runtime key limited to Control Plane Read and Use permissions. |
| `CONTROL_PLANE_TUNNEL_ID` | Required ConfigMap key `control-plane-tunnel-id`; staged as `activation-required` | One tunnel identity associated with both Codex and ChatGPT in the intended organization/workspace. |
| `DO_NOT_TRACK` | Deployment value `1` | Disables runtime usage telemetry. |

Request, search, and parser deadlines default to 20 seconds, 20 seconds, and 15 seconds respectively; parser subprocesses also receive bounded memory, CPU, file-size, and file-descriptor limits. The adapter serializes MCP work, keeps the File Station SID in memory, caps upstream response bodies, sanitizes all public errors, and never logs credentials, SIDs, downloaded content, raw upstream responses, or attacker-controlled paths. Caller paths reject absolute, backslash, NUL, empty, dot, dot-dot, encoded, and double-encoded traversal. Returned links, mount points, remapped roots, and any `real_path` outside `/volume1/Media` fail closed. File Station writes are not exposed; activation must prove that the dedicated non-admin account receives a write denial without creating or mutating a Media file.

PDF, DOCX, XLSX, and PPTX conversion runs in a separate worker with parser networking disabled, MarkItDown plugins disabled, and no LLM, macro, or external-resource execution. Local temporary directories, image buffers, PDF handles, subprocesses and range handlers are cleaned up on success, parser failure, timeout and cancellation. Remote search stop/clean requests are attempted on every exit; an unavailable NAS can prevent remote cleanup and requires an operator check. `ffprobe` receives a minimal environment, an allowlist of local or loopback HTTP protocols and media formats, a 1MiB probe size, a 2-second analysis bound, and a 256KiB output cap; playlists and concat-style inputs are rejected. For a small supported media file the adapter downloads at most 8MiB. For a larger file it exposes an ephemeral loopback range facade, validates every `206 Content-Range` response, and counts all ranges against 64MiB. If the NAS cannot prove a usable range response, the extension is unsupported, or probing fails, `media_info` returns basic verified metadata with `inspection_limited=true` and a specific limitation rather than downloading the full file.

The external bootstrap contract is `mcp-synology-credentials` with key metadata `control-plane-api-key`, `synology-username`, and `synology-password`, plus non-secret `control-plane-tunnel-id` in `mcp-synology-config`. Credential bootstrap is an operator contract, not tested Secret-provisioning automation in this repository; never put values, account IDs, tunnel IDs, or passwords in Git, logs, or inline plaintext commands. The separate NAS certificate-renewal work must first provide a valid certificate for `nas.bohdal.name`; TLS verification remains mandatory and there is no alternate origin or namespace-imperative bypass.

Build and validation run in the repository devcontainer, with each task invoked separately: `mise run mcp-bootstrap`, `mise run mcp-lint`, `mise run mcp-test`, `mise run mcp-manifest-check`, `mise run mcp-container-build`, and `mise run mcp-grafana-check`. The locked test suite covers protocol annotations, authentication retry and expiry, root and link guards, malformed parser inputs, output/time/cleanup limits, cancellation cleanup, and small and large media probing. The trusted `main` image workflow builds the pinned Python `3.14.8` image with source-built `ffprobe 9.0.2` and the verified tunnel runtime for both architectures, publishes a reviewed digest, and never activates Flux. The child remains suspended with zero replicas until the digest, Secret key metadata, certificate, Media root, write denial, and tunnel/client preflights are separately reviewed.
