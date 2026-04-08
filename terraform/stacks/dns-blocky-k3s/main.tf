# Manage the new-cluster Blocky DNS workload in a dedicated root so DNS HA,
# policy, and observability can evolve independently from legacy DNS stacks.
locals {
  # Render Blocky configuration from Terraform variables so local DNS records,
  # blocklists, and telemetry settings remain in committed desired state.
  blocky_config = {
    upstreams = {
      groups = {
        default = var.upstreams
      }
    }
    blocking = {
      denylists = {
        ads = var.denylist_urls
      }
      clientGroupsBlock = {
        default = ["ads"]
      }
    }
    ports = {
      dns  = 53
      http = 4000
    }
    prometheus = {
      enable = var.metrics_enabled
      path   = var.metrics_path
    }
    queryLog = {
      type              = var.query_log_mode
      target            = var.query_log_target
      logRetentionDays  = var.query_log_retention_days
      logRetentionCount = var.query_log_retention_count
      flushInterval     = var.query_log_flush_interval
    }
    log = {
      level   = "info"
      format  = "json"
      privacy = var.log_privacy
    }
    customDNS = {
      customTTL = "5m"
      mapping   = var.custom_dns_records
    }
  }

  blocky_config_yaml = yamlencode(local.blocky_config)
  blocky_config_hash = sha256(local.blocky_config_yaml)
}

resource "kubernetes_namespace_v1" "blocky" {
  metadata {
    name = var.namespace_name
  }
}

# Expose DNS externally through MetalLB on a fixed IP for LAN clients.
resource "kubernetes_service_v1" "blocky_dns" {
  wait_for_load_balancer = false

  metadata {
    name      = var.dns_service_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
    annotations = {
      "metallb.universe.tf/allow-shared-ip"        = "blocky-dns-k3s"
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

# Keep metrics/UI access internal to the cluster while publishing DNS on LB.
resource "kubernetes_service_v1" "blocky_metrics" {
  wait_for_load_balancer = false

  metadata {
    name      = var.metrics_service_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
  }

  spec {
    selector = {
      app = "blocky"
    }

    port {
      name        = "http"
      port        = 4000
      protocol    = "TCP"
      target_port = 4000
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "blocky_logs" {
  metadata {
    name      = var.log_pvc_name
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.log_pvc_size
      }
    }
  }
}

resource "kubernetes_config_map_v1" "blocky" {
  metadata {
    name      = "blocky-config"
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
  }

  data = {
    "config.yaml" = local.blocky_config_yaml
  }
}

# Run Blocky on every node to maximize DNS availability during node failures.
resource "kubernetes_daemon_set_v1" "blocky" {
  wait_for_rollout = false

  metadata {
    name      = "blocky"
    namespace = kubernetes_namespace_v1.blocky.metadata[0].name
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
          image = var.blocky_image

          port {
            container_port = 53
            protocol       = "UDP"
          }

          port {
            container_port = 53
            protocol       = "TCP"
          }

          port {
            container_port = 4000
            protocol       = "TCP"
          }

          env {
            name  = "TZ"
            value = var.blocky_timezone
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
            claim_name = kubernetes_persistent_volume_claim_v1.blocky_logs.metadata[0].name
          }
        }
      }
    }
  }
}
