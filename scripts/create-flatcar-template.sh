#!/usr/bin/env bash

set -euo pipefail

# Create a Flatcar Container Linux VM template on Proxmox VE from the official
# Proxmox image. The resulting template is consumed by Terraform to clone k3s
# cluster nodes.
#
# This script is intended to run directly on the Proxmox host (or via SSH).
# It downloads the Flatcar Proxmox image, creates a VM, imports the disk,
# attaches a cloud-init CD-ROM (required for Ignition delivery), and converts
# the VM into a template.

usage() {
  cat <<'EOF' >&2
Usage:
  create-flatcar-template.sh [options] <template_vm_id>

Options:
  --channel <channel>     Flatcar release channel (stable, beta, alpha). Default: stable
  --version <version>     Flatcar version string. Default: current
  --storage <id>          Proxmox storage ID for the imported disk. Default: local-lvm
  --bridge <bridge>       Network bridge for the template NIC. Default: vmbr0
  --memory <mb>           Default memory in MB. Default: 4096
  --cores <n>             Default CPU cores. Default: 2
  --force                 Destroy existing VM with the same ID before creating.
  -h, --help              Show this help message.

Arguments:
  template_vm_id          Proxmox VM ID to assign to the template.

Examples:
  ./scripts/create-flatcar-template.sh 900
  ./scripts/create-flatcar-template.sh --channel stable --version current --force 900
EOF
  exit 1
}

# Defaults
channel="stable"
flatcar_version="current"
storage="local-lvm"
bridge="vmbr0"
memory=4096
cores=2
force=false
template_vm_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      shift
      [[ $# -gt 0 ]] || usage
      channel="$1"
      ;;
    --version)
      shift
      [[ $# -gt 0 ]] || usage
      flatcar_version="$1"
      ;;
    --storage)
      shift
      [[ $# -gt 0 ]] || usage
      storage="$1"
      ;;
    --bridge)
      shift
      [[ $# -gt 0 ]] || usage
      bridge="$1"
      ;;
    --memory)
      shift
      [[ $# -gt 0 ]] || usage
      memory="$1"
      ;;
    --cores)
      shift
      [[ $# -gt 0 ]] || usage
      cores="$1"
      ;;
    --force)
      force=true
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [[ -z "${template_vm_id}" ]]; then
        template_vm_id="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
  shift
done

[[ -n "${template_vm_id}" ]] || usage

# Verify required tools are available on the Proxmox host.
for tool in wget qm; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Missing required tool: ${tool}" >&2
    exit 1
  fi
done

image_url="https://${channel}.release.flatcar-linux.net/amd64-usr/${flatcar_version}/flatcar_production_proxmoxve_image.img"
image_file="/tmp/flatcar_production_proxmoxve_image.img"
template_name="flatcar-${channel}-${flatcar_version}"

echo "==> Downloading Flatcar ${channel}/${flatcar_version} Proxmox image..."
wget -q --show-progress -O "${image_file}" "${image_url}"

# Optionally destroy an existing VM with the target ID so the script stays
# idempotent when re-run for a version upgrade.
if "${force}"; then
  if qm status "${template_vm_id}" >/dev/null 2>&1; then
    echo "==> Destroying existing VM ${template_vm_id} (--force)..."
    qm destroy "${template_vm_id}" --purge 2>/dev/null || true
  fi
fi

echo "==> Creating VM ${template_vm_id} (${template_name})..."
qm create "${template_vm_id}" \
  --name "${template_name}" \
  --cores "${cores}" \
  --memory "${memory}" \
  --net0 "virtio,bridge=${bridge}" \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0 \
  --ostype l26

echo "==> Importing disk image to ${storage}..."
qm disk import "${template_vm_id}" "${image_file}" "${storage}"

echo "==> Attaching imported disk as scsi0..."
qm set "${template_vm_id}" --scsi0 "${storage}:vm-${template_vm_id}-disk-0"

echo "==> Setting boot order to scsi0..."
qm set "${template_vm_id}" --boot order=scsi0

echo "==> Adding SCSI controller..."
qm set "${template_vm_id}" --scsihw virtio-scsi-pci

# The cloud-init CD-ROM is required even for Ignition-only provisioning.
# Proxmox delivers the user-data (Ignition JSON) through this drive.
echo "==> Adding cloud-init CD-ROM drive on ide2..."
qm set "${template_vm_id}" --ide2 "${storage}:cloudinit"

echo "==> Converting VM ${template_vm_id} to template..."
qm template "${template_vm_id}"

# Clean up the downloaded image to avoid filling /tmp on the Proxmox host.
rm -f "${image_file}"

echo "==> Done. Template '${template_name}' ready as VM ID ${template_vm_id}."
echo "    Use this ID as 'template_vm_id' in the platform-k3s Terraform stack."
