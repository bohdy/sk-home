# Build a reusable stack context for Tailscale and overlay-network resources.
locals {
  # Keep common tags consistent across stacks while still allowing overrides.
  common_tags = merge(
    {
      project      = var.project_name
      environment  = var.environment
      tailnet_name = var.tailnet_name
      stack        = "overlay"
      managed_by   = "terraform"
    },
    var.additional_tags
  )
}

resource "kubernetes_namespace_v1" "tailscale" {
  metadata {
    name = var.kubernetes_namespace
  }
}

resource "kubernetes_secret_v1" "authkey" {
  wait_for_service_account_token = false
  data_wo_revision               = 1

  metadata {
    name      = "${var.tailscale_name}-auth"
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }

  data_wo = {
    TS_AUTHKEY = var.tailscale_authkey
  }

  lifecycle {
    ignore_changes = [
      data_wo_revision,
      wait_for_service_account_token,
    ]
  }
}

resource "kubernetes_service_account_v1" "tailscale" {
  automount_service_account_token = false

  metadata {
    name      = var.tailscale_name
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }
}

resource "kubernetes_role_v1" "tailscale" {
  metadata {
    name      = var.tailscale_name
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "tailscale" {
  metadata {
    name      = var.tailscale_name
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.tailscale.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.tailscale.metadata[0].name
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }
}

resource "kubernetes_deployment_v1" "tailscale" {
  wait_for_rollout = false

  metadata {
    name      = var.tailscale_name
    namespace = kubernetes_namespace_v1.tailscale.metadata[0].name
  }

  spec {
    replicas = var.tailscale_replicas

    selector {
      match_labels = {
        app = var.tailscale_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.tailscale_name
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false
        service_account_name            = kubernetes_service_account_v1.tailscale.metadata[0].name
        host_network                    = true
        dns_policy                      = "ClusterFirstWithHostNet"

        container {
          name  = var.tailscale_name
          image = var.tailscale_image

          env {
            name = "TS_AUTHKEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.authkey.metadata[0].name
                key  = "TS_AUTHKEY"
              }
            }
          }

          env {
            name  = "TS_ROUTES"
            value = var.tailscale_routes
          }

          env {
            name  = "TS_USERSPACE"
            value = "false"
          }

          env {
            name  = "TS_KUBE_SECRET"
            value = "${var.tailscale_name}-state"
          }

          env {
            name  = "TS_HOSTNAME"
            value = var.tailscale_hostname
          }

          env {
            name  = "TS_EXTRA_ARGS"
            value = "--accept-routes=false"
          }

          env {
            name  = "TS_SNAT_SUBNET_ROUTES"
            value = "true"
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              add = ["NET_ADMIN", "NET_RAW"]
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret_v1.authkey,
    kubernetes_role_binding_v1.tailscale,
  ]
}
