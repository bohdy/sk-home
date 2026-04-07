# Use the k3s kubeconfig for both direct Kubernetes resources and Helm-managed
# platform components in this root.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}
