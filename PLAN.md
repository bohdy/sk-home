# Flow and Grafana Cleanup Plan

## Status

This plan is complete on `main` after PRs #252, #253, #254, and #255; live reconciliation and acceptance checks passed.

- `main` was synchronized with `origin/main` at `27339ff` before the cleanup branches were created.
- PRs #251 through #255 are merged; Flux applied the final revision `main@sha1:848321995d9b199ba30a25f65afd5f5489e8cae1`.
- No imperative live deletion or mutation was performed; Flux applied the declared Job and datasource provisioning changes.
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
- Live reconciliation created and completed `Job clickhouse-ddl-d22ch294g8` with matching ConfigMap and volume names, then pruned the old static Job.

### Grafana datasources

The baseline live Grafana API reported three ClickHouse datasources:

- ID `5`: `ClickHouse`, read-only, stale provisioned datasource.
- ID `7`: `Flow ClickHouse`, UID `FlowClickHouse`, currently not read-only, originally created manually.
- ID `6`: `grafana-clickhouse-datasource`, UID `cfu9md4pkr30gc`, unused manual datasource.

The Helm values now declare `Flow ClickHouse IaC` with UID `FlowClickHouseIaC` and `editable: false`; the dashboard references the new UID.

The Grafana datasource sidecar maps certificate-valid `grafana.bohdal.name` to the Grafana process loopback, avoiding both certificate hostname errors and Cloudflare Access redirects. Its certificate validates normally, and its health listener is distinct from the dashboard sidecar's listener.

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
- Map `grafana.bohdal.name` to `127.0.0.1` in the Grafana Pod, use that canonical hostname on port 3000 for the sidecar reload URL, and give the datasource sidecar a distinct health port.
- Retain the explicit deletion ConfigMap as a harmless guard; the final datasource survived the Grafana pod restart performed during Helm reconciliation.

## Validation

1. Completed locally: `kubectl kustomize kubernetes/flux/observability/flow-collector` renders matching hashed Job, ConfigMap, and volume names.
2. Completed locally: `kubectl kustomize kubernetes/flux/observability/metrics` includes the cleanup ConfigMap with no secret data.
3. Completed locally: `kubectl kustomize kubernetes/flux/observability/dashboards` and JSON checks show only `FlowClickHouseIaC` on `sk-flow` panels.
4. Completed locally: targeted pre-commit YAML/JSON checks and `git diff --check` pass.
5. Completed live: Flux applied revision `main@sha1:848321995d9b199ba30a25f65afd5f5489e8cae1`, the DDL Job completed successfully, the Flow Collector Kustomization is Ready, and the old immutable Job is pruned.
6. Completed live: authenticated `/api/datasources` returns exactly one `grafana-clickhouse-datasource` with name `Flow ClickHouse IaC`, UID `FlowClickHouseIaC`, `readOnly: true`, host `clickhouse.observability.svc.cluster.local`, port `8123`, and protocol `http`.
7. Completed live: the `sk-flow` dashboard has six panels using only `FlowClickHouseIaC`; a representative Grafana query succeeded and returned `359764` flow rows, and Grafana health reports database `ok`.

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
