variable "proxmox_endpoint" {
  # Keep the Proxmox API URL outside source control so operators can target the
  # intended environment through Bitwarden or local Terraform variable injection.
  type = string
}

variable "proxmox_api_token" {
  # Treat API tokens as sensitive so Terraform redacts them from CLI output and
  # state-aware diagnostics.
  type      = string
  sensitive = true
}

variable "proxmox_ssh_private_key" {
  # The provider accepts private keys as plain strings; callers may pass escaped
  # newlines and providers.tf normalizes them before opening SSH connections.
  type      = string
  sensitive = true
}

variable "proxmox_ssh_username" {
  # Keep the SSH principal configurable because Proxmox file operations can use
  # a different account than API-token-backed resource operations.
  type = string
}
