variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL."
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token string."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key" {
  description = "Unencrypted Proxmox root SSH key used for snippet uploads."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_username" {
  description = "Username for Proxmox SSH access, typically 'root'."
  type        = string
  default     = "root"
}
