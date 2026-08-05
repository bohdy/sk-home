# Flow and Grafana Cleanup Plan

## Status

This plan is implemented locally on branch `codex/continue-flow-grafana-cleanup`; live reconciliation remains pending publication through the normal pull-request path.

- `main` was synchronized with `origin/main` at `27339ff` before this branch was created.
- PR #251 is merged; its dashboard and metrics changes are already reconciled.
- No live deletion or mutation has been performed for this cleanup task.
- The task-created changes now cover the hashed DDL Job, datasource migration, final datasource UID, dashboard references, and related documentation.
- Leave unrelated untracked files `.devcontainer/devcontainer-lock.json`, `.opencode/`, `ops/`, and `scripts/gha-runner-cleanup.sh` untouched.

## Objective

1. Make the ClickHouse schema workload reconcile safely when its generated SQL ConfigMap changes.
2. Remove stale Grafana ClickHouse datasources and leave exactly one datasource created by IaC.

## Findings

### ClickHouse DDL

- `observability-flow-collector` is NotReady because the existing `Job.batch "clickhouse-ddl"` has an immutable pod template.
- The existing Job completed successfully on `2026-08-04T18:51:03Z`.
- `clickhouse-init.sql` is idempotent through `IF NOT EXISTS`.
- ClickHouse 26.7 rejects the previous combined database-and-table HTTP POST with `Multi-statements are not allowed`; the live Job reached ClickHouse but failed with HTTP 400.
- The generated ConfigMap is named `clickhouse-ddl-<content-hash>`.
- A Kustomize replacement cannot see the generated hash before the name-hash transformer runs, so the failed replacement was replaced with a custom `nameReference` for `Job.metadata.name`.
- Local rendering now contains `Job clickhouse-ddl-4c9c52hdhg`, `ConfigMap clickhouse-ddl-4c9c52hdhg`, and a matching volume reference.

### Grafana datasources

The live Grafana API currently reports three ClickHouse datasources:

- ID `5`: `ClickHouse`, read-only, stale provisioned datasource.
- ID `7`: `Flow ClickHouse`, UID `FlowClickHouse`, currently not read-only, originally created manually.
- ID `6`: `grafana-clickhouse-datasource`, UID `cfu9md4pkr30gc`, unused manual datasource.

The Helm values now declare `Flow ClickHouse IaC` with UID `FlowClickHouseIaC` and `editable: false`; the dashboard references the new UID.

The Grafana datasource sidecar now targets the local HTTPS endpoint, but its `skipTlsVerify` setting only covers Kubernetes API requests; the reload client requires the documented `REQ_SKIP_TLS_VERIFY` environment variable. Without it, the sidecar rejects the local certificate hostname before calling Grafana.

## Implementation

### 1. Fix the DDL workload

- Keep the one-shot `Job` and make its name derive from the generated ConfigMap hash rather than changing the pod template of the static `clickhouse-ddl` Job.
- Use `kustomizeconfig.yaml` to treat the Job's base name as a reference to the generated `clickhouse-ddl` ConfigMap; this is required because the generator hash is applied after ordinary replacements.
- Keep the database and table DDL in separate one-statement files and post them sequentially because ClickHouse's HTTP interface rejects multi-statement requests.
- Render the overlay and require the same `clickhouse-ddl-<content-hash>` name for the Job, ConfigMap, and volume reference.
- Let Flux prune the old static Job and create the new Job through the declared Kustomization; do not delete it manually unless reconciliation proves unable to complete the transition.
- Confirm the new Job completes and `observability-flow-collector` becomes Ready.

### 2. Clean up Grafana declaratively

- Add a hashed, labeled ConfigMap under `kubernetes/flux/observability/metrics/` so the Grafana datasource sidecar provisions a migration file.
- Use an explicit `deleteDatasources` file to delete `ClickHouse`, `grafana-clickhouse-datasource`, and `Flow ClickHouse` in organization `1`.
- Rename the final IaC datasource to `Flow ClickHouse IaC` and `FlowClickHouseIaC`, so deletion and creation cannot collide with the existing manual record during one provisioning pass.
- Keep `editable: false` and update every `sk-flow` dashboard panel to the new UID.
- Add the cleanup ConfigMap to the metrics Kustomization.
- Set the datasource sidecar reload URL to the local HTTPS Grafana endpoint and set `REQ_SKIP_TLS_VERIFY` for the reload client, while retaining `skipTlsVerify` for Kubernetes API access.
- Decide after successful reconciliation whether the explicit deletion ConfigMap should remain as a harmless guard or be removed as one-time migration scaffolding. Do not remove it before verifying the final datasource survives a Grafana restart.

## Validation

1. Completed locally: `kubectl kustomize kubernetes/flux/observability/flow-collector` renders matching hashed Job, ConfigMap, and volume names.
2. Completed locally: `kubectl kustomize kubernetes/flux/observability/metrics` includes the cleanup ConfigMap with no secret data.
3. Completed locally: `kubectl kustomize kubernetes/flux/observability/dashboards` and JSON checks show only `FlowClickHouseIaC` on `sk-flow` panels.
4. Completed locally: targeted pre-commit YAML/JSON checks and `git diff --check` pass.
5. Pending publication and Flux reconciliation: verify the DDL Job completes, the Flow Collector Kustomization is Ready, and no immutable Job error remains. The current live cluster still reports the old `clickhouse-ddl` immutable-template failure.
6. Pending publication and authenticated Grafana access: query `/api/datasources` and require exactly one datasource with type `grafana-clickhouse-datasource`, the final UID, `readOnly: true`, and the expected ClickHouse host. The unauthenticated endpoint currently returns HTTP 401.
7. Pending publication: query the `sk-flow` dashboard and representative panels through Grafana; require successful ClickHouse responses and no stale datasource references.

## Relevant Files

- `kubernetes/flux/observability/flow-collector/clickhouse-ddl-job.yaml`
- `kubernetes/flux/observability/flow-collector/kustomization.yaml`
- `kubernetes/flux/observability/flow-collector/kustomizeconfig.yaml`
- `kubernetes/flux/observability/flow-collector/clickhouse-database.sql`
- `kubernetes/flux/observability/flow-collector/clickhouse-init.sql`
- `kubernetes/flux/clusters/sk-talos/observability/flow-collector-kustomization.yaml`
- `kubernetes/flux/observability/metrics/helm-release.yaml`
- `kubernetes/flux/observability/metrics/kustomization.yaml`
- `kubernetes/flux/observability/metrics/grafana-datasource-cleanup.yaml`
- `kubernetes/flux/observability/dashboards/sk-flow.json`
- `kubernetes/flux/observability/metrics/README.md`
- `kubernetes/flux/observability/dashboards/README.md`
