# Keep the Terraform version requirement aligned across stacks so local tooling
# and CI use a predictable baseline.
terraform {
  required_version = "~> 1.14.8"

  # Pin the provider source and version so gateway interface resources stay
  # aligned with the rest of the MikroTik-managed stacks.
  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "= 1.99.1"
    }
  }
}
