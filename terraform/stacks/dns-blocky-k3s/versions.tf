# Pin the Terraform and Kubernetes provider baselines so the k3s Blocky DNS
# stack stays reproducible across local and CI runs.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
