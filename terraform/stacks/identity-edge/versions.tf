# Keep the Terraform version requirement aligned across stacks so local tooling
# and CI use a predictable baseline.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.18"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
