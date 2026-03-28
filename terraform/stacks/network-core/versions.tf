# Keep the Terraform version requirement aligned across stacks so local tooling
# and CI use a predictable baseline.
terraform {
  required_version = "~> 1.14.8"

  # tflint-ignore: terraform_unused_required_providers
  # Keep the RouterOS provider pinned in the parent root until legacy DHCP
  # objects have been migrated out of the old state.
  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "= 1.99.1"
    }
  }
}
