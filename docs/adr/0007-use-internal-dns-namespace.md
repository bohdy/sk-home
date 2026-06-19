# Use internal DNS namespace

Internal-only LAN service records will live under `internal.bohdal.name`, using explicit names such as `grafana.internal.bohdal.name` and `syslog.internal.bohdal.name` instead of ad hoc `-internal` hostnames or a default wildcard. This keeps canonical public names such as `grafana.bohdal.name` available for Cloudflare Access while making direct LAN and break-glass paths obvious, reviewable, and less likely to mask typos or undeployed services.
