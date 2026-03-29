# Reuse the existing cluster kubeconfig for both direct Kubernetes resources
# and Helm-managed platform components in this root.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}
