# Kubernetes add-ons

This directory contains the Kubernetes-side configuration for the `sk-talos` cluster. Terraform still owns the infrastructure outside Kubernetes, while Flux owns in-cluster add-ons after the first Cilium bootstrap.

Cluster infrastructure add-ons are reconciled as separate Flux `Kustomization` resources so dependencies are explicit. Shared cluster policy reconciles first, Cilium reconciles the LoadBalancer/BGP resources, cert-manager installs before the production ACME issuer, the shared Cloudflare Tunnel connector depends on policy and Cilium, generic Synology CSI storage reconciles after policy and Cilium, and DNS depends on policy and Cilium before publishing the Blocky resolver VIP. The CloudNativePG operator depends on policy and Cilium. The unsuspended namespace-only `shared-postgres-namespace` prerequisite creates the protected `postgres` Namespace for Secret bootstrap. The suspended shared PostgreSQL application depends on that prerequisite, the operator, Cilium and Synology CSI storage; namespace/operator installation and later database activation require reviewed production approval.

## Bootstrap order

Prerequisites for the bootstrap host are `kubectl`, Helm, Bitwarden Secrets Manager CLI, `jq`, and the DNS utility `dig`. Use the repo devcontainer when those tools are available there; otherwise install them on the local workstation before starting.

1. Apply the Talos Terraform stack so the cluster starts without the Talos default CNI or kube-proxy.
2. Retrieve kubeconfig into a local ignored path:

   ```bash
   terraform -chdir=terraform/k3s/talos-cluster output -raw kubeconfig > /tmp/sk-talos-kubeconfig
   chmod 0600 /tmp/sk-talos-kubeconfig
   ```

3. Create the Cilium BGP authentication secret from Bitwarden without printing the value:

   ```bash
   export BGP_MD5_PASSWORD="$(bws secret get 2c67255f-36f4-4344-b94d-b459014e9249 -o json | jq -r .value)"
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n kube-system create secret generic sk-kubernetes-bgp-auth \
     --from-literal=password="${BGP_MD5_PASSWORD}" \
     --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   unset BGP_MD5_PASSWORD
   ```

4. Install Cilium as the first network component:

   ```bash
   helm repo add cilium https://helm.cilium.io/
   helm repo update cilium
   helm upgrade --install cilium cilium/cilium \
     --version 1.19.4 \
     --namespace kube-system \
     --values kubernetes/bootstrap/cilium/values.yaml \
     --kubeconfig /tmp/sk-talos-kubeconfig
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n kube-system rollout status daemonset/cilium
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n kube-system rollout status deployment/cilium-operator
   ```

5. Create the Synology CSI client secret if the storage component should reconcile immediately. Skip this step only if you intentionally want Flux to report the storage component as not ready until the secret is restored.

   ```bash
   export SYNOLOGY_CSI_PASSWORD="$(bws secret get 3c76c84f-2fec-455c-b212-b46e00f63952 -o json | jq -r .value)"
   jq -n --arg password "${SYNOLOGY_CSI_PASSWORD}" \
     '{clients: [{host: "10.1.100.10", port: 5001, https: true, username: "synology-csi", password: $password}]}' \
     > /tmp/synology-client-info.yml

   kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace synology-csi --dry-run=client -o yaml \
     | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n synology-csi create secret generic client-info-secret \
     --from-file=client-info.yml=/tmp/synology-client-info.yml \
     --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

   unset SYNOLOGY_CSI_PASSWORD
   rm -f /tmp/synology-client-info.yml
   ```

   Bitwarden Secrets Manager item `SK-TALOS-SYNO-CSI` stores only the DSM password. The committed documentation owns the non-secret endpoint and username. Do not commit `client-info.yml` or print it in logs.

6. Create the Cloudflare DNS-01 token Secret for cert-manager. Bitwarden item `CLOUDFLARE_API_TOKEN` must contain a token restricted to `Zone:DNS:Edit` and `Zone:Zone:Read` for `bohdal.name`.

   ```bash
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace cert-manager --dry-run=client -o yaml \
     | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   export CLOUDFLARE_API_TOKEN="$(bws secret get 535c2d90-8239-4f6b-a70f-b41b00c9d06c -o json | jq -r .value)"
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n cert-manager create secret generic cloudflare-api-token \
     --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
     --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   unset CLOUDFLARE_API_TOKEN
   ```

7. Apply the committed Flux v2.8.8 controllers and public read-only repository sync:

   ```bash
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply \
     --server-side \
     --kustomize kubernetes/flux/clusters/sk-talos/flux-system
   ```

   The repository is public, so Flux uses HTTPS without a GitHub deploy credential. Write access remains limited to the normal reviewed pull-request workflow.

Keep shell tracing disabled while a Bitwarden value is present. Do not commit kubeconfig or plaintext secret material.

## Certificates

cert-manager lives in `kubernetes/flux/infrastructure/cert-manager`. The dependent `certificates` component owns the production Let's Encrypt ClusterIssuer and uses Cloudflare DNS-01 validation without requiring an ingress controller.

The component README at `kubernetes/flux/infrastructure/cert-manager/README.md` documents the token contract, bootstrap command, validation, and rollback constraints.

## Cloudflare Tunnel

The reusable connector lives in `kubernetes/flux/infrastructure/cloudflare-tunnel`. It runs two fixed replicas for the remotely managed tunnel created by `terraform/cloudflare/tunnel` and reads its connector token from an externally bootstrapped Kubernetes Secret.

The component README documents the Bitwarden item, token bootstrap, and connector validation. Application routes, DNS records, and Cloudflare Access policies are introduced separately with their owning workloads.

## Observability

The staged observability workloads live under `kubernetes/flux/observability`. The first component, `metrics`, installs the pinned VictoriaMetrics Kubernetes stack and Grafana after Cilium and validated Synology storage are Ready.

The metrics component README documents the Grafana credential bootstrap, retained storage, validation, and rollback requirements. The dependent `logs` component deploys VictoriaLogs and provisions Grafana's pinned log data source. The `vector` component collects node-local Kubernetes, Talos, audit, and external syslog records with bounded buffers and source exclusions.

The `base` component owns the shared namespace, its resource defaults, and its aggregate capacity quota before any namespace-scoped observability resource. The reusable `snmp` component pins SNMP Exporter and its reviewed generated vendor modules, with the accepted MikroTik target enabled and remaining devices gated by the explicit inventory and Bitwarden-backed credentials. The `flow-collector` component deploys goflow2 and ClickHouse for MikroTik gateway IPFIX records: the collector exposes UDP/2055 on a reserved VIP, emits NDJSON on stdout, and the existing Vector pipeline routes that stream into the repository-owned `flows.flow` schema with a 30-day TTL and `flows.flow_analytics` internal-network view. Grafana provisions that flow database as `Flow ClickHouse IaC` with stable UID `FlowClickHouseIaC`, and the `sk-flow` dashboard supports observed internal-IP selection, manual override, selected-host analytics, and routed WAN/inter-VLAN flow paths. The independent `flow-geoip` component imports a Bitwarden-backed MaxMind GeoLite2 City database into ClickHouse and supplies adaptive country/city lookup data for direction-aware selected-host external peers. The independent `blackbox` component performs confirmed gateway ICMP, Blocky DNS, Grafana HTTPS, and stable external HTTPS probes through VMAgent. The `proxmox` component uses the OpenTofu-managed read-only identity, verified private-CA TLS, and a restricted multi-target scrape for Proxmox infrastructure metrics. The `alerting` component adds missing Flux and cert-manager coverage plus sustained local rules without duplicating the stack defaults. The `grafana-tls` component issues Grafana's production certificate before its listener and Service are exposed. Critical alert fan-out to Telegram and Discord, warning-only Discord delivery, recovery notifications, grouping, and inhibition have been accepted with self-expiring synthetic alerts.

## MCP runtimes

The independent `mcp-grafana` and `mcp-synology` children are suspended staging integrations. Each has no Service, ingress, PVC, or VIP and starts one non-root tunnel-client process with one stdio MCP child. The child Kustomizations remain independent so Grafana can wait for `observability-metrics` while Synology waits only for Cilium; neither child is an implicit dependency of the other. The staged Deployments have `replicas: 0`, the images and tunnel IDs are `activation-required`, and the ConfigMaps contain no credential values.

The first reviewed GitOps phase unsuspends one child while retaining zero replicas. Flux then creates its restricted, prune-protected namespace, tokenless ServiceAccount, ConfigMap, Deployment, and Cilium policy without starting a runtime; do not create a namespace imperatively to bypass a suspended owner. The next reviewed change bootstraps only the declared Secret metadata through the approved Bitwarden operator contract, replaces the image placeholder with a trusted immutable GHCR digest, and records the actual tunnel identity. A later explicit production approval changes the selected Deployment to one replica. Secret bootstrap is not tested automation in this repository, and no Secret value, account identity, tunnel ID, Viewer token, or password belongs in Git, logs, or inline commands.

Grafana egress permits DNS, the OpenAI control plane, the canonical HTTPS VIP and the translated metrics Grafana pod on port 3000. It uses a dedicated Viewer token and disabled telemetry. The command enables only search, Prometheus, Loki, alerting, dashboard, folder, and navigation categories and disables write, generic datasource, raw API, SQL, admin, proxied, and run-panel-query tools. A standard-library stdio guard around the unchanged official binary checks the fixed 23-tool read-only catalog and rejects unknown tools and missing, nested, aliased, duplicate or conflicting datasource bindings before dispatch. Prometheus query and discovery tools require `datasourceUid=VictoriaMetrics`; Loki tools require `datasourceUid=VictoriaLogs`. Generic datasource metadata and all-datasource health tools are absent. Dashboard and alert payloads may still mention excluded datasource names; these references do not grant backend access. The guard discards child stderr and passes only the Grafana environment, without tunnel credentials. VictoriaLogs uses the supported Loki tools with a 100-entry log limit and 15-second Grafana timeout; callers should narrow selectors and time ranges. The relay bounds each output frame to 4MiB, which is a protocol ceiling, not a universal query-result budget. Existing Grafana metrics and SNMP dashboards remain the NAS diagnostics path.

Synology egress is restricted to DNS, the OpenAI control plane, and TCP/5001 on the pinned NAS address. It accepts only `https://nas.bohdal.name:5001`, keeps TLS verification enabled, and requires the separate certificate-renewal task to repair the currently invalid certificate before activation. The adapter calls File Station `list_share` and accepts the configured `Media` share only when `additional.real_path` is exactly `/volume1/Media`; every returned item must carry a segment-safe `additional.real_path` under that root. The dedicated non-admin identity must pass a write-denial check without creating or mutating a Media file, and tests must reject traversal, links, redirects, remapped roots, and out-of-root paths. Text is capped at 1MiB, documents and images at 25MiB, small media at 8MiB, and large media at a cumulative 64MiB of verified HTTP range transfers; unsupported formats or unverified range behavior return metadata with `inspection_limited=true` and a specific limitation.

Use `scripts/mcp-preflight.sh --static` for credential-free rendering and staged-boundary checks. Use `scripts/mcp-preflight.sh --live grafana` or `scripts/mcp-preflight.sh --live synology` only with a live kubeconfig; the command checks node, Cilium, DNS, Secret key-name, public TLS, image-digest, and tunnel-ID metadata, then exits `3` by design because effective backend permissions, fresh Cilium/DNS and RouterOS return-path evidence, management BGP, strict NAS TLS, root/link behavior, and both Codex/ChatGPT associations remain separate acceptance proofs. A live preflight is not activation approval. Before calling a component accepted, collect fresh provenance-bearing evidence for RouterOS, Cilium, pod DNS, backend and return paths, TLS, Secret metadata, the complete read-only tool surface, Grafana Viewer permissions, NAS write denial and real-path checks, and representative reads of every supported format through both client bindings.

For an active incident, scale the Deployment to zero or delete it, revoke its runtime key, and then suspend its Flux child; suspending Flux alone leaves an already-running process alive. Reconcile the deletion or emergency scale change into Git before resuming the child so Flux does not restart the workload with stale replicas, image, or tunnel identity. Routine changes must be made through reviewed GitOps changes and allowed to reconcile normally.

Use `docs/observability-rollout.md` as the resumable deployment checkpoint and update it after each accepted stage.

## Applications

Stateful application workloads live in `kubernetes/flux/apps` and reconcile through the separate `apps` cluster tree. The `unifi` component provisions retained iSCSI storage, a pinned controller image, a private Tunnel origin, a LAN-only `10.1.30.56` console VIP, and its separate `10.1.30.1` device-communication VIP. Internal DNS resolves the canonical console name to the LAN VIP; the Cloudflare stack owns the same public hostname's Tunnel route and single-identity Access boundary. Its component README defines the required Bitwarden Secret bootstrap and restore/cutover sequence. The optional `observability/unifi-poller` stage consumes a read-only controller service account from Bitwarden-backed Secret `unifi-poller-auth` and is excluded from the automatic observability parent until its child Flux Kustomization is explicitly applied after Secret bootstrap; once activated, Flux manages the child independently and it exports controller-side metrics without replacing the AP SNMP dashboards. The `smtp-relay` component provides the Brother printer's private, STARTTLS-only outbound Postfix path at `smtp.internal.bohdal.name:587`, uses the retained `synology-iscsi-retain` queue claim, and requires the operator-managed `SK-SMTP-RELAY` Bitwarden bootstrap described in its component README.

## Shared PostgreSQL

The [shared PostgreSQL contract](flux/apps/shared-postgres/README.md) defines three CloudNativePG instances on distinct nodes, retained Synology claims and a separate limited database/role for each approved application. LiteLLM is the first configured consumer. The service is internal-only; it creates no public ingress, service VIP or DNS publication. One synchronous standby is required for writes, while all three volumes share the same NAS failure domain. Backups and restore testing are deferred.

The database Flux child stays suspended until secure Bitwarden Secret bootstrap, current cluster/storage checks and a separately reviewed activation change. The unsuspended namespace prerequisite allows Secret bootstrap without activating database workloads; it is the sole owner of the prune-protected `postgres` Namespace. Installing that prerequisite and the operator are production changes requiring approval before merge. Run `mise run shared-postgres-render` for credential-free chart and Kustomize validation; successful rendering does not establish deployment or live acceptance.

## Storage

Generic cluster storage lives in `kubernetes/flux/infrastructure/storage-synology-csi`. It installs the Talos-compatible Synology CSI driver and the explicit-only `synology-iscsi-retain` StorageClass. The Talos image must include `siderolabs/iscsi-tools`, and the `synology-csi/client-info-secret` secret must exist before the component can become ready.

Use the validation checklist in `kubernetes/flux/infrastructure/storage-synology-csi/README.md` before deploying production stateful workloads on this class.

## BGP service VIPs

Cilium allocates `LoadBalancer` service addresses from `10.1.30.0/24` and advertises only those VIP host routes to the MikroTik gateway at `10.1.20.1`. The MikroTik Terraform stack accepts only `/32` routes inside that pool from the Talos node peers.

Use this smoke test after Cilium, Flux, and MikroTik BGP are configured:

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig create deployment lb-smoke --image=nginx:stable-alpine
kubectl --kubeconfig /tmp/sk-talos-kubeconfig expose deployment lb-smoke --port=80 --type=LoadBalancer
kubectl --kubeconfig /tmp/sk-talos-kubeconfig get service lb-smoke
```

The service should receive a `10.1.30.x` external IP and be reachable from a LAN client routed through the MikroTik gateway.

## DNS

The DNS stack lives in `kubernetes/flux/infrastructure/dns`. Blocky is exposed through Cilium LB IPAM at `10.1.30.53` and forwards to a dedicated internal CoreDNS instance. CoreDNS serves the internal `bohdal.name` split-DNS zone and forwards public recursion to DNS4EU Protective + Ad Blocking over DNS-over-TLS.

The detailed decision record is `docs/dns-design.md`. The DNS component README at `kubernetes/flux/infrastructure/dns/README.md` documents source versus rendered files, record updates, smoke tests, and rollback.

Render and validate DNS manifests from the repository root:

```bash
mise run dns-render
mise run dns-check
```

Flux applies the committed rendered manifests from `kubernetes/flux/infrastructure/dns/rendered`. Do not edit rendered DNS files directly.

Before MikroTik DHCP hands out `10.1.30.53`, validate the VIP with direct `dig @10.1.30.53` tests from LAN clients on each relevant VLAN. DHCP changes should be a follow-up after the Kubernetes DNS path is healthy.
