provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  # Snippet uploads still use SSH on Proxmox, so keep the root PAM key wired in
  # even though API token auth covers the rest of the stack.
  ssh {
    username    = "root"
    private_key = replace(var.proxmox_ssh_private_key, "\\n", "\n")
  }
}
