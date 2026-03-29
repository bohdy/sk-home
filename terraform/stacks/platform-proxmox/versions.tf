# Pin the Terraform and Proxmox provider baselines so VM lifecycle behavior
# stays consistent across local runs, review plans, and CI validation.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.99"
    }
  }
}
