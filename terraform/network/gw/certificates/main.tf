# Register one durable ACME account so certificate issuance and renewal can be
# traced by Let's Encrypt without committing its private account key.
resource "acme_registration" "gateway" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email
}

# Generate the ACME-account key inside OpenTofu. It is sensitive state in the
# encrypted backend and is never emitted as an output, log line, or artifact.
resource "tls_private_key" "acme_account" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# DNS-01 preserves Cloudflare proxying and never exposes RouterOS management
# ports to the Internet. OpenTofu renews when fewer than 30 days remain.
resource "acme_certificate" "gateway" {
  account_key_pem    = acme_registration.gateway.account_key_pem
  common_name        = "gw.bohdal.name"
  key_type           = "P256"
  min_days_remaining = 30

  dns_challenge {
    provider = "cloudflare"

    config = {
      CF_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

# Import the full trusted chain and its matching private key directly into the
# gateway. Rotation replaces this object whenever ACME issues a new leaf.
resource "routeros_system_certificate" "gateway" {
  # Derive the RouterOS object name from the immutable certificate content so
  # renewal can install the replacement before moving www-ssl away from the
  # still-serving previous certificate.
  name        = "gw-bohdal-name-${substr(sha256(acme_certificate.gateway.certificate_pem), 0, 12)}"
  common_name = acme_certificate.gateway.common_name
  trusted     = true

  import {
    cert_file_content = "${acme_certificate.gateway.certificate_pem}${acme_certificate.gateway.issuer_pem}"
    key_file_content  = acme_certificate.gateway.private_key_pem
  }

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [acme_certificate.gateway.certificate_pem]
  }
}

# WebFig and the HTTPS REST endpoint share www-ssl. Limiting it to the home
# address space prevents a valid certificate from becoming Internet exposure.
import {
  # www-ssl is a built-in RouterOS service, so adopt it before changing its
  # certificate or listener policy instead of attempting to create a duplicate.
  to = routeros_ip_service.www_ssl
  id = "www-ssl"
}

resource "routeros_ip_service" "www_ssl" {
  numbers     = "www-ssl"
  port        = 443
  address     = "10.0.0.0/8"
  certificate = routeros_system_certificate.gateway.name
  tls_version = "only-1.2"
  disabled    = false
}
