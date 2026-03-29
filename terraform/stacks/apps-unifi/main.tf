# Manage the Cloudflare entrypoint and the in-cluster UniFi application objects
# together so the external hostname and adopted workload stay in sync.
resource "cloudflare_dns_record" "unifi" {
  zone_id = var.cloudflare_zone_id
  name    = "unifi"
  type    = "CNAME"
  ttl     = 1
  content = "${var.cloudflare_tunnel_id}.cfargotunnel.com"
  proxied = true
  comment = "Managed by Pulumi - Unifi Tunnel Ingress"
}

resource "cloudflare_zero_trust_access_application" "unifi" {
  zone_id                   = var.cloudflare_zone_id
  name                      = "Unifi"
  domain                    = var.domain
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
  enable_binding_cookie     = false
  options_preflight_bypass  = false

  policies = [
    {
      id         = var.shared_access_policy_id
      precedence = 1
    }
  ]
}

resource "kubernetes_namespace_v1" "unifi" {
  metadata {
    name = var.namespace_name
  }
}

resource "kubernetes_secret_v1" "mongo" {
  data_wo_revision               = 1
  wait_for_service_account_token = false

  metadata {
    name      = var.mongo_secret_name
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  data_wo = {
    "mongo-root-password" = var.mongo_root_password
  }

  lifecycle {
    ignore_changes = [
      data_wo_revision,
      wait_for_service_account_token,
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "mongo" {
  metadata {
    name      = var.mongo_pvc_name
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_service_v1" "mongo" {
  wait_for_load_balancer = false

  metadata {
    name      = "unifi-mongo"
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
  }

  spec {
    selector = {
      app = "unifi-mongo"
    }

    port {
      port        = 27017
      target_port = 27017
    }
  }
}

resource "kubernetes_deployment_v1" "mongo" {
  wait_for_rollout = false

  metadata {
    name      = var.mongo_deployment_name
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "unifi-mongo"
      }
    }

    template {
      metadata {
        labels = {
          app = "unifi-mongo"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "mongodb"
          image             = "mongo:4.4"
          args              = ["--wiredTigerCacheSizeGB", "0.5"]
          image_pull_policy = "IfNotPresent"

          env {
            name  = "MONGO_INITDB_ROOT_USERNAME"
            value = "admin"
          }

          env {
            name = "MONGO_INITDB_ROOT_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mongo.metadata[0].name
                key  = "mongo-root-password"
              }
            }
          }

          port {
            container_port = 27017
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }

            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "mongo-data"
            mount_path = "/data/db"
          }
        }

        volume {
          name = "mongo-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.mongo.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "unifi" {
  metadata {
    name      = var.unifi_pvc_name
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_service_v1" "device" {
  wait_for_load_balancer = false

  metadata {
    name      = "unifi-device-communication"
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "metallb.universe.tf/ip-allocated-from-pool" = "production-pool"
    }
  }

  spec {
    type = "LoadBalancer"
    selector = {
      app = "unifi"
    }

    port {
      name        = "inform"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "stun"
      port        = 3478
      target_port = 3478
      protocol    = "UDP"
    }

    port {
      name        = "discovery"
      port        = 10001
      target_port = 10001
      protocol    = "UDP"
    }
  }
}

resource "kubernetes_service_v1" "gui" {
  wait_for_load_balancer = false

  metadata {
    name      = "unifi-gui"
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
  }

  spec {
    selector = {
      app = "unifi"
    }

    port {
      name        = "https-gui"
      port        = 8443
      target_port = 8443
    }
  }
}

resource "kubernetes_deployment_v1" "unifi" {
  wait_for_rollout = false

  metadata {
    name      = var.unifi_deployment_name
    namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    annotations = {
      "pulumi.com/autonamed" = "true"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "unifi"
      }
    }

    template {
      metadata {
        annotations = var.unifi_pod_annotations
        labels = {
          app = "unifi"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "unifi"
          image             = "linuxserver/unifi-network-application:latest"
          image_pull_policy = "Always"

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Europe/Prague"
          }

          env {
            name  = "MEM_LIMIT"
            value = "2048"
          }

          env {
            name  = "MEM_STARTUP"
            value = "2048"
          }

          env {
            name  = "MONGO_HOST"
            value = kubernetes_service_v1.mongo.metadata[0].name
          }

          env {
            name  = "MONGO_PORT"
            value = "27017"
          }

          env {
            name  = "MONGO_DBNAME"
            value = "unifi"
          }

          env {
            name  = "MONGO_AUTHSOURCE"
            value = "admin"
          }

          env {
            name  = "MONGO_USER"
            value = "admin"
          }

          env {
            name = "MONGO_PASS"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mongo.metadata[0].name
                key  = "mongo-root-password"
              }
            }
          }

          port {
            container_port = 8443
          }

          port {
            container_port = 8080
          }

          port {
            container_port = 3478
            protocol       = "UDP"
          }

          port {
            container_port = 10001
            protocol       = "UDP"
          }

          liveness_probe {
            initial_delay_seconds = 180
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3

            tcp_socket {
              port = 8443
            }
          }

          readiness_probe {
            initial_delay_seconds = 120
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6

            tcp_socket {
              port = 8443
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }

            limits = {
              cpu    = "2"
              memory = "3Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/config"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.unifi.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.mongo,
    kubernetes_service_v1.mongo,
  ]
}

resource "kubernetes_manifest" "servers_transport" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "ServersTransport"
    metadata = {
      name      = "skip-tls"
      namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    }
    spec = {
      insecureSkipVerify = true
    }
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "unifi-tls-cert"
      namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    }
    spec = {
      secretName = "unifi-tls-cert"
      dnsNames   = [var.domain]
      issuerRef = {
        name = var.cluster_issuer_name
        kind = "ClusterIssuer"
      }
    }
  }
}

resource "kubernetes_manifest" "ingress_route" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "unifi-route"
      namespace = kubernetes_namespace_v1.unifi.metadata[0].name
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`${var.domain}`)"
          kind  = "Rule"
          services = [
            {
              name             = kubernetes_service_v1.gui.metadata[0].name
              port             = "https-gui"
              serversTransport = "skip-tls"
            }
          ]
        }
      ]
      tls = {
        secretName = "unifi-tls-cert"
      }
    }
  }

  depends_on = [
    kubernetes_manifest.servers_transport,
    kubernetes_manifest.certificate,
    kubernetes_deployment_v1.unifi,
  ]
}
