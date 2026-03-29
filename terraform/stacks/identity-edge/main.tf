# Build a reusable stack context for Cloudflare edge identity resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project       = var.project_name
      environment   = var.environment
      access_domain = var.access_domain
      stack         = "identity-edge"
      managed_by    = "terraform"
    },
    var.additional_tags
  )

  tunnel_token = base64encode(jsonencode({
    a = var.cloudflare_account_id
    t = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
    s = var.tunnel_secret_b64
  }))
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  config_src    = var.tunnel_config_source
  tunnel_secret = var.tunnel_secret_b64

  lifecycle {
    ignore_changes = [tunnel_secret]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster.id

  config = {
    ingress = concat([
      for hostname in var.tunnel_ingress_hostnames : {
        hostname       = hostname
        service        = var.tunnel_origin_service
        origin_request = { no_tls_verify = true }
      }
      ], [
      {
        service = "http_status:404"
      }
    ])
  }
}

resource "cloudflare_zero_trust_access_group" "allowed_users" {
  account_id = var.cloudflare_account_id
  name       = "Allowed Users"

  include = [
    {
      email = {
        email = var.allowed_user_email
      }
    }
  ]
}

resource "cloudflare_zero_trust_access_policy" "allow_policy" {
  account_id = var.cloudflare_account_id
  name       = "Access Policy"
  decision   = "allow"

  include = [
    {
      email = {
        email = var.allowed_user_email
      }
    }
  ]

  session_duration = "24h"
}

resource "kubernetes_namespace_v1" "cloudflared" {
  metadata {
    name = var.kubernetes_namespace
  }
}

resource "kubernetes_secret_v1" "tunnel_token" {
  data_wo_revision               = 1
  wait_for_service_account_token = false

  metadata {
    name      = var.cloudflared_secret_name
    namespace = kubernetes_namespace_v1.cloudflared.metadata[0].name
  }

  data_wo = {
    token = local.tunnel_token
  }

  lifecycle {
    ignore_changes = [
      data_wo_revision,
      wait_for_service_account_token,
    ]
  }
}

resource "kubernetes_deployment_v1" "cloudflared" {
  wait_for_rollout = false

  metadata {
    name      = var.cloudflared_deployment_name
    namespace = kubernetes_namespace_v1.cloudflared.metadata[0].name
  }

  spec {
    replicas = var.cloudflared_replicas

    selector {
      match_labels = {
        app = var.cloudflared_deployment_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.cloudflared_deployment_name
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        security_context {
          supplemental_groups = [0]
        }

        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key      = "app"
                  operator = "In"
                  values   = [var.cloudflared_deployment_name]
                }
              }

              topology_key = "kubernetes.io/hostname"
            }
          }
        }

        container {
          name  = var.cloudflared_deployment_name
          image = var.cloudflared_image
          args  = ["tunnel", "--no-autoupdate", "run"]

          env {
            name = "TUNNEL_TOKEN"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.tunnel_token.metadata[0].name
                key  = "token"
              }
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 65532
            run_as_group               = 65532
            allow_privilege_escalation = false
          }
        }
      }
    }
  }
}
