# Kubernetes add-ons

This directory contains the Kubernetes-side configuration for the `sk-talos` cluster. Terraform still owns the infrastructure outside Kubernetes, while Flux owns in-cluster add-ons after the first Cilium bootstrap.

Cluster infrastructure add-ons are reconciled as separate Flux `Kustomization` resources so dependencies are explicit. Shared cluster policy reconciles first, Cilium reconciles the LoadBalancer/BGP resources, cert-manager installs before the production ACME issuer, the shared Cloudflare Tunnel connector depends on policy and Cilium, generic Synology CSI storage reconciles after policy and Cilium, and DNS depends on policy and Cilium before publishing the Blocky resolver VIP.

## Bootstrap order

Prerequisites for the bootstrap host are `kubectl`, Helm, Bitwarden Secrets Manager CLI, and `jq`. Use the repo devcontainer when those tools are available there; otherwise install them on the local workstation before starting.

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

The metrics component README documents the Grafana credential bootstrap, retained storage, validation, and rollback requirements. The dependent `logs` component deploys VictoriaLogs and provisions Grafana's pinned log data source. The `vector` component then collects node-local Kubernetes logs with bounded buffers and source exclusions. External syslog, exporters, public Grafana routing, and notification delivery remain later dependency-ordered components.

Use `docs/observability-rollout.md` as the resumable deployment checkpoint and update it after each accepted stage.

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
