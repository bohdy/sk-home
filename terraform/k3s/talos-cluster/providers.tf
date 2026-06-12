terraform {
  # Pin OpenTofu and provider versions so the Talos cluster can be rebuilt
  # reproducibly while this repo is being restored in small, reviewable steps.
  required_version = "1.12.1"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.6.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # Proxmox snippet uploads and some VM image operations still require SSH even
  # when API-token authentication is used for normal resource management.
  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = replace(var.proxmox_ssh_private_key, "\\n", "\n")
  }
}
