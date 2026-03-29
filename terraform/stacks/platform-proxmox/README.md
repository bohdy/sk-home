# Platform Proxmox

This stack is the Terraform destination for the existing Pulumi `sk-infra` domain.

It targets the live Proxmox VM inventory for `k8s-master`, `k8s-worker-1`, `k8s-worker-2`, `vm-openclaw`, the four existing cloud-init snippets in `local:snippets`, and the `victoriametrics` metrics server.

The cluster-node cloud-init snippets still render secret-bearing bootstrap values such as the kubeadm token and Docker credentials. The stack is import-safe without those Bitwarden values because the rendered snippet payload is currently ignored for drift, but fully authoritative snippet management should wait until `K8S_TOKEN`, `DOCKER_USERNAME`, `DOCKER_PASSWORD`, and `DOCKER_AUTH_BASE64` are available to the shared Bitwarden loader.

Current migration status:
- The snippet files and the metrics server can be imported into Terraform state.
- The current `bpg/proxmox` VM resource import path appears broken for these guests: the provider asks for `node/id` formatting and then fails while refreshing the imported state.
- The Proxmox file resource also treats declared upload sources as replacement-only, so a future first apply would rewrite the imported snippet files even if their names stay stable.
