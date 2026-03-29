# Platform Proxmox

This stack is the Terraform destination for the existing Pulumi `sk-infra` domain.

It targets the live Proxmox VM inventory for `k8s-master`, `k8s-worker-1`, `k8s-worker-2`, `vm-openclaw`, the four existing cloud-init snippets in `local:snippets`, and the `victoriametrics` metrics server.

The cluster-node cloud-init snippets render secret-bearing bootstrap values such as the kubeadm token and Docker credentials. The stack derives the Docker username and password from `DOCKER_AUTH_BASE64` when the older standalone secrets are missing, so the recovery path does not need duplicate Docker secrets in Bitwarden.

Current migration status:
- The snippet files, metrics server, and VMs can be imported into Terraform state.
- The working VM import ID format is `pve/<vmid>` for this stack. The previously tried `vm/pve/<vmid>` form is broken for this provider/resource combination.
- The committed snippet templates stay in the repository as source of truth for recovery, but snippet uploads are disabled by default so normal platform plans do not try to recreate them.
- Setting `manage_imported_snippet_payloads = true` enables an explicit recovery or reprovisioning pass and fails closed unless `K8S_TOKEN` plus Docker auth values resolve to a real username and password.
- The VM resource still treats clone metadata as create-only, so `declare_clone_source` remains disabled by default after import.
