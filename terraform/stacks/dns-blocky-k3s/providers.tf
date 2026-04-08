# Use the selected k3s kubeconfig so this stack can manage the in-cluster
# Blocky DNS resources directly.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}
