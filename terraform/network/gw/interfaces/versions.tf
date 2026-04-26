terraform {
  # Pin Terraform and provider versions so RouterOS behavior stays reproducible
  # while the rebuilt repo is still being learned and validated in small steps.
  required_version = "1.14.9"

  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.1"
    }
  }
}
