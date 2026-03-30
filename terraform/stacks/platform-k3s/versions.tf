# Pin the Terraform and provider baselines so Flatcar VM lifecycle and Butane
# transpilation behave consistently across local runs and CI validation.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.99"
    }
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.13"
    }
  }
}
