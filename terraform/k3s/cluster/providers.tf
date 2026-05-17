provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  # VM lifecycle operations can require SSH access for Proxmox-side file and
  # guest operations, so keep SSH configured alongside API-token auth.
  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = replace(var.proxmox_ssh_private_key, "\\n", "\n")
  }
}

provider "ct" {}
