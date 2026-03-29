# Connect this stack to the existing Cloudflare zone and Kubernetes cluster so
# Terraform can adopt and manage the live UniFi application resources.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
