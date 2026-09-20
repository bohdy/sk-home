# Second Brain (staged)

The Flux child for this component remains `suspend: true`, and the three image references remain `activation-required`; those tags are placeholders and cannot start a release. Publishing image metadata must not change the suspend flag. The companion Cloudflare stack prepares `brain.bohdal.name` behind the existing exact-owner Google Access policy and routes to the private web Service on port 8080. Neither that stack nor this staged Flux child has been applied; no live workload or public route is activated by this patch. No Ingress, LoadBalancer, Gateway, internal DNS/VIP, RouterOS rule, or Secret payload is introduced.

The `second-brain` namespace contains one Recreate Deployment with API, worker, and web containers and one PostgreSQL 17 StatefulSet named `brain-db`. The API listens on 8000, the web container listens on 8080, and the worker has no Service port. API and worker mount `brain-assets` at `/data/assets`; the claim is ReadWriteOnce, and Recreate stops the old pod before creating a replacement. The database uses a separate `brain-database` ReadWriteOnce claim and is configured for UID/GID 999; the backend contract uses 10001 and the web contract uses 101. Both claims request `synology-iscsi-retain` and are marked to survive Flux pruning. Verify the live StorageClass reclaim policy before activation; claim retention is not a backup, so approve and test a separate encrypted backup and restore process before storing irreplaceable data.

## Runtime contract

| Setting | Source / purpose |
| --- | --- |
| `BRAIN_ASSET_ROOT` | ConfigMap; `/data/assets`, shared asset directory |
| `BRAIN_PROVIDER` | ConfigMap; `manual` is the default and needs no third-party AI credential |
| `BRAIN_API_TOKEN` | Required key in `brain-runtime`; use at least 24 characters for mandatory API bearer authentication |
| `BRAIN_DATABASE_URL` | Required key in `brain-runtime`; PostgreSQL URL targets `brain-db:5432/brain` and must use the database Secret password |
| `POSTGRES_PASSWORD` | Required key in `brain-postgres-auth`; initializes database role `brain` |
| `.dockerconfigjson` | Required key in `ghcr-pull`, type `kubernetes.io/dockerconfigjson`; authenticates private GHCR image pulls |

All three Secrets belong in namespace `second-brain`. Provision them through the approved Bitwarden-backed mechanism and verify only names, key names, and types; never commit Secret payloads, credentials, connection URLs containing passwords, or example real tokens. A compatible AI endpoint is optional and may add provider variables to `brain-runtime` only after its runtime contract is tested. Telegram is disabled: no Telegram process runs in this base. Enabling it requires a reviewed deployment addition, bot token, allowed user IDs, and the same private API authentication boundary.

The backend image contract runs as UID/GID 10001. Its migration init container runs `python -m brain.migrate`, retries database connectivity, takes the advisory migration lock, and exits on migration failure before API or worker startup. The worker runs `python -m brain.worker` and refreshes its heartbeat on each loop; the exec probe runs `python -m brain.worker_health` and fails when the heartbeat is older than 600 seconds. The API listens on 8000 and must expose `/health/live` and `/health/ready`; the web image runs as UID/GID 101 and listens on 8080. PostgreSQL is configured for UID/GID 999 and keeps `PGDATA` in a claim subdirectory so initialization does not collide with filesystem metadata. Verify these image identities, commands, probes, and PostGIS/pgvector extensions against the published images before activation.

## Activation prerequisites

1. Publish and verify immutable digests for `ghcr.io/bohdy/brain-backend`, `ghcr.io/bohdy/brain-web`, and `ghcr.io/bohdy/brain-db`, then update the Kustomize `images` entries through a scoped GitHub App pull request. The update must preserve `suspend: true`; image publication must never unsuspend the Flux child.
2. Verify live Flux, Cilium, `synology-iscsi-retain`, storage capacity, PVC ownership behavior, DNS, actual cluster/service/node CIDRs, and network-policy enforcement. This staging change includes no live prerequisite evidence. Test permitted public IPv4 HTTP/HTTPS and denied private, metadata, and special-use destinations, including redirects and the reviewed exclusions `192.31.196.0/24`, `192.52.193.0/24`, `192.88.99.0/24`, and `192.175.48.0/24`.
3. Provision `brain-runtime`, `brain-postgres-auth`, and `ghcr-pull` without exposing their values. Verify only key names and Secret types, and configure the database URL for the custom database image's role, password, and service.
4. Run migrations on a disposable database, exercise authenticated API and browser flows, confirm unauthenticated content access fails, and test asset persistence through a pod restart. Verify `/health/live`, `/health/ready`, and the worker heartbeat probe, and inspect aggregate `/metrics` output for private labels before adding any scrape integration.
5. Obtain explicit production activation approval, then change the Flux child's `suspend` field to `false` through the reviewed GitOps path. Do not remove the staging guard or enable live reconciliation as a side effect of image publication.

All Services are ClusterIP. The additional tunnel ingress policy grants only the `cloudflare-tunnel` namespace, `cloudflared` pod label, and `cloudflared` service account TCP 8080 access; it grants no direct API or database access. Cloudflare Access authenticates the existing exact owner through Google, and application bearer authentication remains required. The authorized read-only Cloudflare plan passed on 2026-09-20: create the Second Brain Access application and proxied DNS record, and update only its route in the shared tunnel. Existing routes were unchanged, and the owner identity and private web origin matched configuration. No apply was performed. An approved operator can run `kubectl -n second-brain port-forward service/second-brain 8080:8080` for local browser access; the browser supplies the API token, and nginx proxies `/api` to the `api` Service on port 8000. Cilium permits kubelet probes and same-application API/database connections, DNS to the cluster resolver, and public IPv4 TCP 80/443 egress from the application pods only. Private and special-use IPv4 ranges are excluded, and IPv6 outbound connections have no allow rule. No Ingress, Gateway, public Service, RouterOS change, or metrics scrape is staged. These policies do not replace mandatory authentication or application URL validation; the application must reject private resolutions and unsafe redirects.

## Validation and rollback

Run these renders and the repository hooks inside the devcontainer:

```bash
mise exec -- kubectl kustomize kubernetes/flux/apps/second-brain
mise exec -- kubectl kustomize kubernetes/flux/clusters/sk-talos/apps
mise exec -- kubectl kustomize kubernetes/flux/clusters/sk-talos
mise exec -- pre-commit run --all-files
```

The manifest-validation workflow renders this component on pull requests without infrastructure credentials. Rendering checks syntax and composition, not cluster compatibility, image contents, storage readiness, policy enforcement, or application authentication.

After activation, suspend the Flux child and scale down or remove workloads through an approved operational change when processing must stop; suspension alone does not stop running pods. Removing the child with `prune: true` may remove its workloads and Services, while the namespace and PVC prune-disabled annotations protect the namespace and claims. Never delete the namespace, claims, or retained volumes as a rollback shortcut. Do not downgrade PostgreSQL or reverse database migrations as an application rollback; use the tested backup and restore procedure or ship a forward-compatible fix in a new reviewed image and manifest change.
