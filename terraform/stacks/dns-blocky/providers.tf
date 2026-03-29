# Use the existing cluster kubeconfig so this stack can manage the in-cluster
# Blocky namespace, service, storage, and daemonset resources directly.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}
