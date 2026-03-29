# Pin the Terraform and Kubernetes provider baselines so the adopted Blocky
# resources converge predictably across local and CI validation runs.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
