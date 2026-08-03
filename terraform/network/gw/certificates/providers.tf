terraform {
  # Pin providers so issuance and RouterOS import behavior remain reproducible.
  required_version = "1.12.1"

  required_providers {
    acme = {
      source  = "vancluever/acme"
      version = "2.48.3"
    }

    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }
  }
}

provider "acme" {
  # Use the production endpoint because the certificate is installed on the
  # user-facing RouterOS HTTPS service rather than being a staging test.
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

provider "routeros" {
  hosturl  = var.mikrotik_hosturl
  username = var.mikrotik_username
  password = var.mikrotik_password

  # Normal runs verify the freshly issued certificate. The one-time recovery
  # dispatch may override this only while replacing the known expired leaf.
  insecure = var.mikrotik_insecure
}
