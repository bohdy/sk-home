# Pin the Terraform and provider baselines for the observability stack so Helm
# and Kubernetes behavior stays reproducible across environments.
terraform {
  required_version = "~> 1.14.8"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
