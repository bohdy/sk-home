# Reuse the existing cluster kubeconfig for direct Kubernetes objects and Helm
# releases so observability resources converge in one Terraform root.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}
