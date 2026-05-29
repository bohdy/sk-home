# Kubernetes add-ons

This directory contains the Kubernetes-side configuration for the `sk-talos` cluster. Terraform still owns the infrastructure outside Kubernetes, while Flux owns in-cluster add-ons after the first Cilium bootstrap.

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

5. Bootstrap Flux v2.8.8 to reconcile the cluster path in this repository:

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

## BGP service VIPs

Cilium allocates `LoadBalancer` service addresses from `10.1.30.0/24` and advertises only those VIP host routes to the MikroTik gateway at `10.1.20.1`. The MikroTik Terraform stack accepts only `/32` routes inside that pool from the Talos node peers.

Use this smoke test after Cilium, Flux, and MikroTik BGP are configured:

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig create deployment lb-smoke --image=nginx:stable-alpine
kubectl --kubeconfig /tmp/sk-talos-kubeconfig expose deployment lb-smoke --port=80 --type=LoadBalancer
kubectl --kubeconfig /tmp/sk-talos-kubeconfig get service lb-smoke
```

The service should receive a `10.1.30.x` external IP and be reachable from a LAN client routed through the MikroTik gateway.
