# Pin the Terraform and provider baselines so this imported workload stays
# reproducible across local runs and GitHub Actions validation.
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
