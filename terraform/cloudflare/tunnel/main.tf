# The tunnel is shared cluster infrastructure. Application-specific public
# hostnames and Access policies are added only with their owning workload.
resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

# Route only Grafana through the shared tunnel. The origin keeps end-to-end TLS
# and validates the cert-manager certificate against the canonical hostname.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster.id

  config = {
    ingress = [
      {
        hostname = var.grafana_hostname
        service  = var.grafana_origin_service
        origin_request = {
          http_host_header   = var.grafana_hostname
          origin_server_name = var.grafana_hostname
          no_tls_verify      = false
          connect_timeout    = 10
          tls_timeout        = 10
        }
      },
      {
        # Unmatched public hostnames remain fail-closed.
        service = "http_status:404"
      },
    ]
  }
}

# Adopt the existing proxied record instead of replacing it. Public DNS routes
# to the tunnel while internal split DNS continues resolving the same name to
# Grafana's fixed Cilium LoadBalancer address.
import {
  to = cloudflare_dns_record.grafana
  id = "${var.cloudflare_zone_id}/94dea7d9e24ce33427f871c9b7bb0409"
}

resource "cloudflare_dns_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = var.grafana_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Grafana through the shared sk-talos tunnel; managed by OpenTofu"
}

# Resolve the committed ID through the API so a deleted or replaced identity
# provider makes planning fail before the Access policy can change.
data "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id           = var.cloudflare_account_id
  identity_provider_id = var.google_identity_provider_id
}

# Independent MFA must be enabled at the Zero Trust organization before an
# application can require a Cloudflare-managed second factor after Google.
# Preserve the existing organization presentation while adopting its state.
import {
  to = cloudflare_zero_trust_organization.account
  id = var.cloudflare_account_id
}

resource "cloudflare_zero_trust_organization" "account" {
  account_id                                  = var.cloudflare_account_id
  name                                        = "bohdy.cloudflareaccess.com"
  auth_domain                                 = "bohdy.cloudflareaccess.com"
  session_duration                            = "24h"
  deny_unmatched_requests                     = false
  deny_unmatched_requests_exempted_zone_names = []

  login_design = {
    background_color = "#9922ff"
    logo_path        = "https://upload.wikimedia.org/wikipedia/commons/8/8f/Homm3-logo.svg"
    header_text      = "Pro prihlaseni se zakousni do bavorske klobasky..."
    footer_text      = "Disclaimer: for fun use only"
  }

  mfa_config = {
    allowed_authenticators = ["totp", "security_key", "biometrics"]
    session_duration       = "8h"
  }
}

# Cloudflare Access is an additional perimeter. The exact Google identity must
# complete an independent Access-managed factor before Grafana's own login.
resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id                 = var.cloudflare_account_id
  name                       = "Grafana"
  domain                     = var.grafana_hostname
  type                       = "self_hosted"
  allowed_idps               = [data.cloudflare_zero_trust_access_identity_provider.google.id]
  auto_redirect_to_identity  = true
  session_duration           = "8h"
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "strict"
  mfa_config = {
    allowed_authenticators = ["totp", "security_key", "biometrics"]
    mfa_disabled           = false
    session_duration       = "8h"
  }

  policies = [
    {
      name       = "Allow exact owner through Google and independent MFA"
      decision   = "allow"
      precedence = 1
      include = [
        {
          email = {
            email = lower(trimspace(var.grafana_access_email))
          }
        },
      ]
      require = [
        {
          login_method = {
            id = data.cloudflare_zero_trust_access_identity_provider.google.id
          }
        },
      ]
    },
  ]

  lifecycle {
    precondition {
      condition     = data.cloudflare_zero_trust_access_identity_provider.google.type == "google"
      error_message = "The configured Cloudflare Access identity provider must remain Google."
    }
  }

  depends_on = [cloudflare_zero_trust_organization.account]
}

# Cloudflare generates the connector token from the remotely managed tunnel.
# OpenTofu marks it sensitive, but remote state and any explicit output consumer
# must still be treated as credential-bearing.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
}
