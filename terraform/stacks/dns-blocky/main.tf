# Manage the migrated Blocky DNS workload in one root so service exposure,
# storage, rendered config, and pod rollout behavior stay aligned.
locals {
  blocky_config_yaml = file("${path.module}/config.yaml")
  blocky_config_hash = sha256(local.blocky_config_yaml)
}

resource "kubernetes_namespace_v1" "blocky" {
  metadata {
    name = var.namespace_name
  }
}

resource "kubernetes_service_v1" "blocky" {
  wait_for_load_balancer = false

  metadata {
    name      = var.service_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
    annotations = {
      "metallb.universe.tf/allow-shared-ip"        = "blocky-dns"
      "metallb.universe.tf/ip-allocated-from-pool" = "production-pool"
      "metallb.universe.tf/loadBalancerIPs"        = var.dns_ip
    }
  }

  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Local"
    selector = {
      app = "blocky"
    }

    port {
      name        = "dns-udp"
      port        = 53
      protocol    = "UDP"
      target_port = 53
    }

    port {
      name        = "dns-tcp"
      port        = 53
      protocol    = "TCP"
      target_port = 53
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "blocky" {
  metadata {
    name      = var.pvc_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = "128Mi"
      }
    }
  }
}

resource "kubernetes_config_map_v1" "blocky" {
  metadata {
    name      = var.config_map_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  data = {
    "config.yaml" = local.blocky_config_yaml
  }
}

resource "kubernetes_daemon_set_v1" "blocky" {
  wait_for_rollout = false

  metadata {
    name      = var.daemonset_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "blocky"
      }
    }

    template {
      metadata {
        annotations = {
          "config-hash" = local.blocky_config_hash
        }
        labels = {
          app = "blocky"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name  = "blocky"
          image = "spx01/blocky:main"

          port {
            container_port = 53
            protocol       = "UDP"
          }

          port {
            container_port = 53
            protocol       = "TCP"
          }

          env {
            name  = "BLOCKY_LOG_LEVEL"
            value = "info"
          }

          env {
            name  = "TZ"
            value = "Europe/Prague"
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config.yml"
            sub_path   = "config.yaml"
          }

          volume_mount {
            name       = "logs"
            mount_path = "/logs"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.blocky.metadata[0].name
          }
        }

        volume {
          name = "logs"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.blocky.metadata[0].name
          }
        }
      }
    }
  }
}
