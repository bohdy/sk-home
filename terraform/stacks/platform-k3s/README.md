# Platform k3s

This stack provisions a k3s Kubernetes cluster on Flatcar Container Linux VMs running on Proxmox VE.

## Architecture

- **OS**: Flatcar Container Linux (immutable, auto-updating) provisioned via Ignition (Butane YAML transpiled at plan time by the `poseidon/ct` provider and referenced through Proxmox custom cloud-init user-data snippets).
- **Ignition transport**: Proxmox `initialization.user_data_file_id` with per-node snippets (`cicustom` under the hood). The stack intentionally avoids QEMU `fw_cfg`/`kvm_arguments`, which require elevated Proxmox privileges (`root@pam`) in many environments.
- **k3s**: Installed by a first-boot systemd oneshot (`k3s-install.service`) that downloads the pinned release binary and then starts either `k3s.service` (server) or `k3s-agent.service` (agents).
- **Topology**: One server node (control plane with embedded SQLite) and N agent nodes. The built-in Traefik and ServiceLB are disabled so the `cluster-core` stack can manage MetalLB BGP and a separate Traefik Helm release.
- **Network**: Static IP configuration is delivered in two places: systemd-networkd units in the Butane templates (for early boot and Ignition fetch) plus Proxmox `ipconfig`/DNS cloud-init metadata as an operational fallback.
- **Interface naming**: The Butane templates now match `e*` interface names so both `eth0`-style and predictable `ens*` naming work without manual per-node edits.

## Prerequisites

1. Create a Flatcar VM template on Proxmox using `scripts/create-flatcar-template.sh`.
2. Generate a k3s cluster token and store it in Bitwarden Secrets Manager as `K3S_TOKEN`.
3. Load Terraform credentials: `eval "$(./scripts/load-bitwarden-secrets.sh terraform)"`.

## Node Inventory

All cluster nodes are defined in the `nodes` variable map. To add a node, append an entry and apply:

```hcl
nodes = {
  k3s-server-1 = { vm_id = 110, ip = "x.x.x.10", role = "server" }
  k3s-agent-1  = { vm_id = 111, ip = "x.x.x.11", role = "agent" }
  k3s-agent-2  = { vm_id = 112, ip = "x.x.x.12", role = "agent" }
  k3s-agent-3  = { vm_id = 113, ip = "x.x.x.13", role = "agent" }  # new node
}
```

Each entry supports optional `memory` (default 6144), `cores` (default 2), and `disk_size` (default 32) overrides. The stack validates that exactly one node is marked `role = "server"`.

## Scaling Workflow

1. Add a new `k3s-agent-*` entry to `nodes` with a unique `vm_id` and IP.
2. Run `terraform plan` and verify only the new node is created.
3. Apply and wait for the node to join.
4. Validate from kubeconfig: `kubectl get nodes -o wide`.

## Day-2 Recovery

### Rebuild one broken agent VM

```sh
terraform apply \
  -replace='proxmox_virtual_environment_vm.node["k3s-agent-1"]'
```

### Rebuild both agents

```sh
terraform apply \
  -replace='proxmox_virtual_environment_vm.node["k3s-agent-1"]' \
  -replace='proxmox_virtual_environment_vm.node["k3s-agent-2"]'
```

### Refresh kubeconfig from server

Use `terraform output kubeconfig_fetch_hint` and run the printed command.

## Flatcar Template

The helper script creates a Proxmox VM template from the official Flatcar Proxmox image:

```sh
# Run on the Proxmox host (or via SSH):
./scripts/create-flatcar-template.sh --channel stable --force 900
```

The resulting template ID is passed to Terraform as `template_vm_id`.

## Recovery Notes

Ignition runs during first boot. Changing the Butane templates in this stack updates Terraform's rendered Ignition snippets for new or reprovisioned nodes, but it does not rewrite existing Flatcar node files in place. For existing nodes that already booted with a bad interface config, rebuild or reprovision the affected VM so it consumes the corrected Ignition payload. The stack also mirrors static IP/DNS via Proxmox cloud-init metadata (`ipconfig` and `nameserver`) so nodes remain reachable even if early boot networking is delayed.
