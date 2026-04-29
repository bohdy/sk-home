terraform {
  # Pin Terraform and provider versions so RouterOS behavior stays reproducible
  # while the rebuilt repo is still being learned and validated in small steps.
  required_version = "1.14.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.104.0"
    }
  }
}
