terraform {
  # Pin the latest stable provider available when this stack was introduced so
  # Cloudflare v5 schema changes remain deliberate.
  required_version = "1.12.1"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
