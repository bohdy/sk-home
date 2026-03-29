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
