# Observability rollout

This document is the resumable execution checkpoint for the observability implementation defined by `docs/observability-design.md`. Update it after each merged deployment stage so a later session can continue from repository and cluster facts instead of conversation history.

## Current checkpoint

The cluster foundations are deployed and healthy:

- Talos node names are deterministic, and one general-purpose 4 vCPU/8 GiB worker is available.
- Flux v2.8.8 reconciles the cluster from `main`.
- Cilium, cert-manager v1.20.1, the production Let's Encrypt `ClusterIssuer`, and Synology CSI are Ready.
- The `synology-iscsi-retain` StorageClass passed provisioning, persistence, cross-node reattachment, expansion, and retained-volume validation.
- The shared Cloudflare Tunnel has two `cloudflared` 2026.7.2 replicas and a catch-all 404 route. Grafana is not routed through it yet.
- The retained storage validation PV remains intentionally preserved for later manual cleanup.

The metrics stage is implemented but not yet committed, reviewed, merged, or reconciled. The active branch is `deploy-metrics-stack`, with manifests under `kubernetes/flux/observability/metrics` and the cluster wiring under `kubernetes/flux/clusters/sk-talos/observability`.

The in-cluster `observability` namespace and `grafana-admin` Secret have already been bootstrapped. Bitwarden Secrets Manager item `SK-TALOS-GRAFANA-ADMIN-PASSWORD` stores only the Grafana administrator password; the Kubernetes Secret uses the `admin-user` and `admin-password` keys. Never print the secret value or commit rendered Secret data.

## Immediate next actions

1. Render both the metrics component and the complete cluster Kustomization in the repository devcontainer.
2. Run every repository-defined formatting, linting, schema, and hygiene check that applies to the changed files.
3. Inspect the complete diff, verify that no secret value or generated credential is present, and create a signed commit.
4. Push `deploy-metrics-stack`, open a pull request into `main`, merge it after checks pass, and wait for Flux reconciliation.
5. Diagnose any `OCIRepository`, `HelmRelease`, custom-resource, scheduling, or PVC failure before proceeding.
6. Verify the deployed stack and record the result in this document.

The metrics deployment must not be considered accepted until all of these checks pass:

- `observability-metrics` and its source and Helm release report Ready.
- VMSingle, VMAgent, VMAlert, Alertmanager, Grafana, kube-state-metrics, and node exporter are healthy without repeated restarts.
- VictoriaMetrics has a retained 100 GiB `synology-iscsi-retain` PVC, Grafana has a retained 10 GiB PVC, and Alertmanager has its configured retained volume.
- VMSingle reports a one-year retention period.
- VMAgent has expected Kubernetes targets and successfully writes samples to VMSingle.
- Queries return the stable `cluster="sk-talos"` and `site="sk"` labels.
- Grafana starts with the bootstrapped administrator credential, has a working VictoriaMetrics data source, and preserves a temporary test dashboard across a pod restart.
- Worker scheduling, node conditions, memory use, and storage use show enough headroom for the next stage.

If the Alertmanager storage field is rejected by the operator or does not produce a PVC, correct the `VMAlertmanager` specification using the installed CRD schema before acceptance. Do not work around persistence by switching it to ephemeral storage.

## Remaining stages

After metrics acceptance, use a fresh branch from current `main` for each coherent stage:

1. Deploy VictoriaLogs Single with a retained 50 GiB volume and 30-day retention.
2. Deploy Vector as a DaemonSet for Kubernetes logs, then add TCP/UDP syslog on a fixed Cilium LoadBalancer VIP with original sender preservation.
3. Add Talos service and kernel log forwarding and verify the supported Talos audit-event delivery path without request or response bodies.
4. Add SNMP Exporter, committed target inventory, and reviewed SNMPv2c/SNMPv3 modules for MikroTik, UniFi APs, Synology, APC UPS, and Brother printer; treat the printer as intermittent.
5. Add the read-only Proxmox exporter and Blackbox Exporter probes.
6. Add focused dashboards, actionable alert rules, inhibition, Telegram delivery for critical alerts, Discord delivery for critical and warning alerts, and no push delivery for info alerts.
7. Publish only Grafana through a fixed LAN VIP, browser-trusted TLS, split DNS, the shared Cloudflare Tunnel, and Cloudflare Access restricted to the approved Gmail identity with MFA.
8. Run the complete acceptance suite from `docs/observability-design.md`, then update this checkpoint with measured ingestion, resource use, and any deferred debt.

Do not combine later stages merely to reduce pull-request count. Stop progression on dropped data, repeated restarts, storage or worker pressure, unexpected public exposure, secret leakage, or excessive alert noise.

## Secret inventory

Bitwarden Secrets Manager remains the source of truth. Kubernetes Secrets are manually bootstrapped with shell tracing disabled and values passed directly from `bws` without echoing or writing them to the repository.

Known item names needed by the rollout are:

- `SK-TALOS-GRAFANA-ADMIN-PASSWORD`: Grafana administrator password only
- `SK-TALOS-CLOUDFLARED-TOKEN`: shared Cloudflare Tunnel connector token only
- `CLOUDFLARE_API_TOKEN`: narrowly scoped DNS-01 token only
- `SK-TALOS-SYNO-CSI`: Synology CSI DSM password only

Create dedicated Bitwarden items before the stages that require SNMPv2c, SNMPv3, Proxmox, Telegram, or Discord credentials. Document each item's value contract next to its bootstrap procedure; never store a whole configuration block when the documented contract calls for a single credential.

## Deferred debt

Keep the design document's follow-up list authoritative. In particular, traces, Moonraker/Klipper monitoring, UniFi Poller, automated Bitwarden reconciliation, raw telemetry backup, NetFlow or sFlow, and an external dead-man monitor remain deferred.
