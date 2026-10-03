# LiteLLM OSS gateway

This native Kustomize component stages the free LiteLLM OSS proxy and a dedicated PostgreSQL database in namespace `litellm`. The Flux child starts with `suspend: true`; merging the manifests stages the component, and activation follows Secret bootstrap, review and the approved production GitOps path. No Enterprise licence is configured. Access starts with the private ClusterIP Service and a localhost operator port-forward, following the existing application convention.

One Recreate Deployment runs exactly one worker (`--num_workers 1`) using the official nonroot image `ghcr.io/berriai/litellm-non_root:v1.103.2`, pinned to OCI digest `sha256:bee25ffdd3952562401cd1cb844f2b925f006ea8102d719b6d311cc844594d6c`. Redis is omitted because both replicas and workers are one; review Redis coordination before increasing either count or introducing multiple gateway instances. Recreate prevents overlap during rollout and startup migrations, so rollout causes a short outage. The image entrypoint performs Prisma migrations; no concurrent migration Job or separate schema-updater is introduced.

The database uses `docker.io/library/postgres:18.6-bookworm`, pinned to OCI index digest `sha256:3725f4e2499eef5134592b3b4ab79a543ed7f8e533b05b5b637af926630f6650`. Its single StatefulSet ordinal owns the 10 GiB ReadWriteOnce `litellm-database` claim on `synology-iscsi-retain`. PostgreSQL 18 mounts `/var/lib/postgresql` with `PGDATA=/var/lib/postgresql/18/docker`. Namespace and PVC pruning are disabled. The operator explicitly deferred backups for this task; volume retention does not provide backup or restore coverage.

## Runtime and credential contract

| Setting | Source and purpose |
| --- | --- |
| `DATABASE_URL` | Required `litellm-runtime` key; PostgreSQL URL for service `litellm-db`, port 5432, database and role `litellm`; must use the same password as the database Secret |
| `LITELLM_MASTER_KEY` | Required `litellm-runtime` key; random `sk-` prefixed administrative API key |
| `LITELLM_SALT_KEY` | Required `litellm-runtime` key; persistent random encryption salt for provider credentials stored in PostgreSQL; preserve across restarts and replacements |
| `UI_USERNAME`, `UI_PASSWORD` | Required `litellm-runtime` keys; dedicated Admin UI login credentials |
| `POSTGRES_PASSWORD` | Required `litellm-postgres-auth` key; initializes database role `litellm`; changing the Secret alone does not rotate an existing database password |
| `STORE_MODEL_IN_DB` | Committed `True`; persist models configured through the authenticated UI |
| `LITELLM_LOG` | Committed `ERROR`; omit detailed/debug logging |
| `model_list` | Committed empty list; no provider endpoint, model or credential is invented |

Both Secrets belong in namespace `litellm` and must be provisioned from Bitwarden Secrets Manager through the approved operator bootstrap. There is no Secret payload or new secret-controller installation in this component. Verify Secret names, key names and types only; never print values, place passwords in command arguments, commit connection URLs containing credentials, or capture them in CI artifacts. Percent-encode password characters correctly when preparing `DATABASE_URL`. Preserve the salt alongside the database; replacing it can make stored provider credentials unreadable. Keep provider keys in Bitwarden as their source of truth and supply actual values only through the authenticated Admin UI after activation.

The empty model list is intentional. A healthy gateway and UI do not prove upstream inference or spend accounting: add an actual provider and model supplied by the operator, then verify an authenticated request and its usage/spend record. `store_prompts_in_spend_logs: false`, `disable_error_logs: true`, and `turn_off_message_logging: true` retain spend tracking while excluding prompt/response logging and the database error-log view. Do not enable payload logs or debugging while diagnosing credentials. Verify the pinned version actually honours these settings before production use with sensitive prompts.

The proxy runs as UID/GID 65534 and PostgreSQL as UID/GID 999, with no service-account token, privilege escalation or Linux capabilities. Both root filesystems are read-only. The proxy init container copies UI/assets, including dotfiles, from the official image into bounded writable emptyDir volumes; runtime paths also provide migrations, general cache and temporary storage. Baked image Prisma engine paths under `/opt/prisma` remain intact. PostgreSQL receives writable socket and temporary volumes alongside its data claim. Ephemeral limits bound writable scratch space; resource sizes are initial committed defaults and should be adjusted from observed usage in a reviewed change.

## Activation and access

1. Render the component and cluster trees and run repository hygiene checks in the devcontainer. Verify immutable image identities, UID contracts, the retained StorageClass and available NAS capacity. Confirm Flux, Cilium, cluster policy, CSI and DNS are Ready.
2. Bootstrap the two required Secrets safely and verify their metadata. Confirm the database URL/password contract without exposing either value. No provider key is needed for gateway startup.
3. Complete review and production approval, then change only the Flux child suspension guard through the reviewed GitOps path. Never apply an unreviewed branch directly to production. Wait for the database PVC, StatefulSet, proxy readiness and Flux child to become Ready.
4. Verify migrations, restart persistence, UI authentication, unauthenticated API rejection, permitted public HTTPS and denied private/metadata egress. Verify that explicit namespace rules admit database ingress only from proxy pods and deny DB outbound traffic. The inherited Cilium local-node trust described below remains an ingress exception; this component does not enforce host isolation. HTTP readiness proves gateway/database availability, not provider connectivity.
5. Add the operator-supplied provider/model through authenticated administration and verify actual inference plus its usage/spend entry before claiming an operational LLM route.

After activation, run this inside the repository devcontainer using the kubeconfig prepared by the [cluster bootstrap](../../../README.md):

```bash
mise exec -- kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n litellm port-forward --address 127.0.0.1 service/litellm 4000:4000
```

The command binds port 4000 to the devcontainer loopback interface. Before opening `http://127.0.0.1:4000/ui` in an operator browser, configure and verify a localhost forwarding path from that browser machine to the devcontainer; container and remote-host loopback addresses are separate. No browser forwarding path or live UI access has been verified for this staged component. The OpenAI-compatible API is at the same localhost base URL and requires an administrative or generated virtual key. Use dedicated virtual keys for clients after initial setup instead of distributing the master key. Keep the forward bound to localhost.

Cilium selects all namespace endpoints with default deny in both directions. The explicit namespace rules admit node-origin TCP 4000 to proxy pods for kubelet probes and operator forwarding, and proxy-to-database TCP 5432. The proxy may resolve DNS through the cluster resolver and reach public IPv4 HTTPS TCP 443, with private and special-use CIDRs excluded. The database has no explicit outbound allow rule or node-wide ingress rule. The existing Cilium configuration does not set `allow-localhost=policy`, so Cilium implicitly permits ingress from the local node and its hostNetwork workloads, including to the database. This component inherits that node trust, does not enforce host isolation, and makes no cluster-wide policy change. See the official [Cilium host policy guidance](https://docs.cilium.io/en/stable/security/policy/layer3/#host). No HTTP/IPv6 public egress, LoadBalancer, DNS record, ingress, tunnel or RouterOS rule is added. Provider endpoints requiring private addresses, HTTP or IPv6 need a separate reviewed policy change.

## Validation and rollback

```bash
mise exec -- kubectl kustomize kubernetes/flux/apps/litellm
mise exec -- kubectl kustomize kubernetes/flux/clusters/sk-talos/apps
mise exec -- kubectl kustomize kubernetes/flux/clusters/sk-talos
mise exec -- pre-commit run --all-files
```

The manifest-validation workflow renders this component without infrastructure credentials on its isolated pull-request runner. Rendering verifies composition and syntax; live tests must verify image behaviour, migrations, storage, Cilium enforcement and authentication. `/health/liveliness` monitors the process, and `/health/readiness` checks gateway/database readiness; no provider health-check traffic is configured.

Suspending Flux stops reconciliation but leaves running workloads running. Stop workloads through a reviewed operational change when necessary. Removing the child may prune Deployments, StatefulSets and Services, while the namespace and PVC remain protected. Never delete the namespace or retained claim as rollback. Do not downgrade PostgreSQL or reverse Prisma migrations blindly; use a forward-compatible fix. Backup/restore work remains explicitly deferred.

Runtime path, health and privacy contracts follow the official [production guidance](https://docs.litellm.ai/docs/proxy/prod), [health guidance](https://docs.litellm.ai/docs/proxy/health), [deployment guidance](https://docs.litellm.ai/docs/proxy/deploy), and [security/encryption guidance](https://docs.litellm.ai/docs/proxy/security_encryption_faq), checked through Context7 for this implementation.
