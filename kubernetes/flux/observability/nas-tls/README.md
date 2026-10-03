# NAS TLS monitoring

This independently suspended child monitors the existing DSM endpoint without authenticating to it. The blackbox target is the fixed unauthenticated `SYNO.API.Info` path at `https://10.1.100.10:5001`; the strict HTTPS module receives `nas.bohdal.name` for SNI and certificate verification. Its additive Cilium rule grants the existing blackbox exporter only TCP/5001 to `10.1.100.10/32` and does not change the shared module configuration.

The rules distinguish the served certificate from the cert-manager source. Existing cert-manager expiry rules remain authoritative for the source Secret; this child adds served-leaf expiry, ready-condition, missing-probe, and KSM CronJob failure/stale-success alerts. Enable this child only after the separate DSM bootstrap and recurring delivery gates are accepted and a fresh read-only preflight has succeeded.
