terraform {
  # Pin Terraform and provider versions so Proxmox image management stays reproducible
  # while the rebuilt repo is still being learned and validated in small steps.
  required_version = ">= 1.15.3"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0"
    }
    ct = {
      source  = "poseidon/ct"
      version = "0.14.0"
    }
  }
}
