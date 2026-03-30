# Platform k3s

This stack provisions a k3s Kubernetes cluster on Flatcar Container Linux VMs running on Proxmox VE.

## Architecture

- **OS**: Flatcar Container Linux (immutable, auto-updating) provisioned via Ignition (Butane YAML transpiled at plan time by the `poseidon/ct` provider).
- **k3s**: Installed as a systemd-sysext image from the Flatcar sysext-bakery. Automated minor-version updates are handled by `systemd-sysupdate`.
- **Topology**: One server node (control plane with embedded SQLite) and N agent nodes. The built-in Traefik and ServiceLB are disabled so the `cluster-core` stack can manage MetalLB BGP and a separate Traefik Helm release.
- **Network**: Static IP configuration is delivered via systemd-networkd units inside the Butane templates rather than through Proxmox cloud-init `ipconfig`. This ensures Ignition has network connectivity during the initramfs fetch stage when it downloads the k3s sysext image.

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

Each entry supports optional `memory` (default 6144), `cores` (default 2), and `disk_size` (default 32) overrides.

## Flatcar Template

The helper script creates a Proxmox VM template from the official Flatcar Proxmox image:

```sh
# Run on the Proxmox host (or via SSH):
./scripts/create-flatcar-template.sh --channel stable --force 900
```

The resulting template ID is passed to Terraform as `template_vm_id`.
