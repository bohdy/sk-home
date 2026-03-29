# Keep the Terraform version requirement aligned across stacks so local tooling
# and CI use a predictable baseline.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
