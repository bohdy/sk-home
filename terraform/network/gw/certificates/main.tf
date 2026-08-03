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

  # The authoritative dns.bohdal.name server publishes Cloudflare-created TXT
  # records just after the provider's default two-minute check window. Wait a
  # conservative five minutes before asking Let's Encrypt to validate DNS-01.
  propagation_wait = 300

  dns_challenge {
    provider = "cloudflare"

    config = {
      CF_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

# Parse the intermediate certificate so its RouterOS object has the certificate
# subject as its required common name without duplicating that value in config.
data "routeros_x509" "gateway_issuer" {
  data = acme_certificate.gateway.issuer_pem
}

# Import the intermediate separately from the leaf. RouterOS creates one
# certificate object per PEM in an import, while the provider locates the
# imported object by name. Splitting the chain keeps that lookup unambiguous.
resource "routeros_system_certificate" "gateway_issuer" {
  # This must be known while OpenTofu creates the immutable plan. Do not derive
  # it from the newly issued PEM: the provider's import callback would then
  # query RouterOS with an empty name.
  name        = "letsencrypt-gateway-issuer"
  common_name = data.routeros_x509.gateway_issuer.common_name
  trusted     = true

  import {
    cert_file_content = acme_certificate.gateway.issuer_pem
  }

  lifecycle {
    # A stable RouterOS name cannot be created alongside an object with the
    # same name. Replace the issuer before recreation rather than relying on
    # RouterOS to allocate a suffixed, ambiguous name.
    replace_triggered_by = [acme_certificate.gateway.issuer_pem]
  }
}

# Import the ACME leaf and its matching private key directly into the gateway.
# A static object name is known at plan time and uniquely identifies this
# single-PEM import to the RouterOS provider.
resource "routeros_system_certificate" "gateway" {
  name        = "letsencrypt-gateway"
  common_name = acme_certificate.gateway.common_name
  trusted     = true

  import {
    cert_file_content = acme_certificate.gateway.certificate_pem
    key_file_content  = acme_certificate.gateway.private_key_pem
  }

  lifecycle {
    # See the issuer lifecycle above. The replacement occurs before the
    # dependent service command selects the newly imported certificate.
    replace_triggered_by = [acme_certificate.gateway.certificate_pem]
  }

  depends_on = [routeros_system_certificate.gateway_issuer]
}

# The provider cannot read the gateway's built-in www-ssl service because
# RouterOS returns duplicate names with unstable IDs. Use RouterOS's documented
# `ip service set www-ssl` command after importing the certificate instead of
# attempting provider adoption. This is a narrow, documented break-glass path
# that preserves the intended declarative certificate lifecycle.
resource "terraform_data" "configure_www_ssl" {
  input = routeros_system_certificate.gateway.name

  triggers_replace = [acme_certificate.gateway.certificate_pem]

  provisioner "local-exec" {
    # The certificate workflow runs Linux self-hosted runners. Bash keeps the
    # request construction fail-closed and prevents accidental word splitting.
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      set -euo pipefail
      payload="$(jq -cn --arg certificate "$ROUTEROS_CERTIFICATE_NAME" '{
        script: (
          "/ip/service/set www-ssl port=443 address=10.0.0.0/8 "
          + "certificate=" + $certificate
          + " tls-version=only-1.2 disabled=no"
        )
      }')"
      curl --fail --silent --show-error ${var.mikrotik_insecure ? "--insecure" : ""} \
        --user "$ROUTEROS_USERNAME:$ROUTEROS_PASSWORD" \
        --header "content-type: application/json" \
        --data "$payload" \
        "${trimsuffix(var.mikrotik_hosturl, "/")}/rest/execute"
    EOT

    environment = {
      # Keep credentials in the process environment, never in the command,
      # plan artifact, OpenTofu output, or GitHub Actions log text.
      ROUTEROS_USERNAME         = var.mikrotik_username
      ROUTEROS_PASSWORD         = var.mikrotik_password
      ROUTEROS_CERTIFICATE_NAME = routeros_system_certificate.gateway.name
    }
  }

  depends_on = [routeros_system_certificate.gateway]
}
