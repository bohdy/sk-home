# Platform Proxmox

This stack is the Terraform destination for the existing Pulumi `sk-infra` domain.

It targets the live Proxmox VM inventory for `k8s-master`, `k8s-worker-1`, `k8s-worker-2`, `vm-openclaw`, the four existing cloud-init snippets in `local:snippets`, and the `victoriametrics` metrics server.

The cluster-node cloud-init snippets still render secret-bearing bootstrap values such as the kubeadm token and Docker credentials. The stack is import-safe without those Bitwarden values because the rendered snippet payload is currently ignored for drift, but fully authoritative snippet management should wait until `K8S_TOKEN`, `DOCKER_USERNAME`, `DOCKER_PASSWORD`, and `DOCKER_AUTH_BASE64` are available to the shared Bitwarden loader.

Current migration status:
- The snippet files, metrics server, and VMs can be imported into Terraform state.
- The working VM import ID format is `pve/<vmid>` for this stack. The previously tried `vm/pve/<vmid>` form is broken for this provider/resource combination.
- The Proxmox file resource treats declared upload sources as replacement-only, and the VM resource treats clone metadata as create-only. Both are therefore disabled by default through import-safe variables until a later pass intentionally re-manages those birth-time attributes.
