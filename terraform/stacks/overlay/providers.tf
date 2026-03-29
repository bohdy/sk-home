# Use the existing cluster kubeconfig because the overlay stack currently
# derives part of its migrated state from in-cluster resources.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}
