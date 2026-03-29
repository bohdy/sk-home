# Connect the identity-edge stack to both Cloudflare and the existing cluster
# because the migrated edge configuration spans Zero Trust and in-cluster data.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
