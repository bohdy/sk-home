variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

variable "site_name" {
  description = "Logical site name used by the Proxmox platform stack."
  type        = string
  default     = "primary"
}

variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

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

variable "template_vm_id" {
  description = "Template VM ID cloned for the imported Ubuntu guests."
  type        = number
  default     = 1000
}

variable "proxmox_node_name" {
  description = "Single Proxmox node that currently hosts the imported VMs."
  type        = string
  default     = "pve"
}

variable "bohdy_username" {
  description = "Primary Linux username preserved in the imported cloud-init payloads."
  type        = string
  default     = "bohdy"
}

variable "bohdy_ssh_public_key" {
  description = "Primary SSH public key preserved in the imported VM bootstrap snippets."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB0Ql0coSrrDTpGmN7BDs9GtxHk0RX4HX8bQNmF+hQb viktor@bohdal.name"
}

variable "github_actions_proxmox_ssh_public_key" {
  description = "GitHub Actions SSH public key preserved for Proxmox-hosted bootstrap automation."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINEsEk/EtCQnPgDFXtMLzJMtbsS+D1eW11fP9r8JYTkC github-actions-proxmox"
}

variable "k8s_token" {
  description = "Existing kubeadm bootstrap token rendered into the cluster-node cloud-init snippets."
  type        = string
  sensitive   = true
  default     = "__MIGRATION_PLACEHOLDER__"
}

variable "docker_username" {
  description = "Docker registry username rendered into the imported cluster bootstrap snippets."
  type        = string
  sensitive   = true
  default     = "__MIGRATION_PLACEHOLDER__"
}

variable "docker_password" {
  description = "Docker registry password rendered into the imported cluster bootstrap snippets."
  type        = string
  sensitive   = true
  default     = "__MIGRATION_PLACEHOLDER__"
}

variable "docker_auth_base64" {
  description = "Base64 Docker auth payload rendered into the imported cluster bootstrap snippets."
  type        = string
  sensitive   = true
  default     = "__MIGRATION_PLACEHOLDER__"
}

variable "manage_imported_snippet_payloads" {
  description = "When true, Terraform actively uploads the Proxmox snippet payloads instead of only adopting the existing files."
  type        = bool
  default     = false
}

variable "declare_clone_source" {
  description = "When true, Terraform records the original clone source metadata for imported VMs even though the provider treats it as create-only."
  type        = bool
  default     = false
}
