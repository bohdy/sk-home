# Keep the Terraform version requirement aligned across roots that reuse this
# module so plans stay predictable across local runs and CI.
terraform {
  required_version = "~> 1.14.8"

  # Pin the RouterOS provider so interface resources behave consistently across
  # the gateway and switch-specific roots.
  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "= 1.99.1"
    }
  }
}
