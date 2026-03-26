# Keep the Terraform version requirement aligned across stacks so local tooling
# and CI use a predictable baseline.
terraform {
  required_version = ">= 1.5.0"

  # Pin the provider source and a known recent version so MikroTik resources
  # can be added consistently across environments.
  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.92.0"
    }
  }
}
