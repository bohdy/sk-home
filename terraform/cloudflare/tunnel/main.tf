# The tunnel is shared cluster infrastructure. Application-specific public
# hostnames and Access policies are added only with their owning workload.
resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

# A terminal catch-all prevents the empty reusable tunnel from proxying any
# request until an explicit reviewed application route is introduced.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster.id

  config = {
    ingress = [
      {
        service = "http_status:404"
      },
    ]
  }
}

# Cloudflare generates the connector token from the remotely managed tunnel.
# OpenTofu marks it sensitive, but remote state and any explicit output consumer
# must still be treated as credential-bearing.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
}
