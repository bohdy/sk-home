# Kubernetes add-ons

This directory contains the Kubernetes-side configuration for the `sk-talos` cluster. Terraform still owns the infrastructure outside Kubernetes, while Flux owns in-cluster add-ons after the first Cilium bootstrap.

Cluster infrastructure add-ons are reconciled as separate Flux `Kustomization` resources so dependencies are explicit. Shared cluster policy reconciles first, Cilium reconciles the LoadBalancer/BGP resources, generic Synology CSI storage reconciles after policy and Cilium, and DNS depends on policy and Cilium before publishing the Blocky resolver VIP.

## Bootstrap order

Prerequisites for the bootstrap host are `kubectl`, Helm, Flux CLI v2.8.8, Bitwarden Secrets Manager CLI, and `jq`. Use the repo devcontainer when those tools are available there; otherwise install them on the local workstation before starting.

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
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace synology-csi --dry-run=client -o yaml \
     | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n synology-csi create secret generic client-info-secret \
     --from-file=client-info.yml=/path/to/client-info.yml \
     --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
   ```

   Store the DSM host, port, username, and password in Bitwarden Secrets Manager. Do not commit `client-info.yml` or print it in logs.

6. Bootstrap Flux v2.8.8 to reconcile the cluster path in this repository:

   ```bash
   flux bootstrap github \
     --owner=bohdy \
     --repository=sk-home \
     --branch=main \
     --path=./kubernetes/flux/clusters/sk-talos \
     --version=v2.8.8 \
     --toleration-keys=node-role.kubernetes.io/control-plane,node-role.kubernetes.io/master \
     --personal
   ```

Keep shell tracing disabled while the Bitwarden value is present. Do not commit kubeconfig, generated Flux credentials, or plaintext BGP authentication material.

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
