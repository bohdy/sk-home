locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.observability_site_name
      stack       = "observability"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Materialize the committed non-secret Grafana and exporter assets so the
  # stack can import the current monitoring namespace without regenerating
  # config from the retired Pulumi code path.
  blackbox_config                = file("${path.module}/config/blackbox.yml")
  vmagent_scrape_config          = file("${path.module}/config/vmagent-prometheus.yml")
  grafana_dashboard_providers    = file("${path.module}/config/dashboardproviders.yaml")
  grafana_datasources            = replace(file("${path.module}/config/datasources.yaml"), "__VICTORIA_METRICS_URL__", "http://victoria-metrics:8428")
  grafana_dashboard_klipper      = file("${path.module}/dashboards/klipper-overview.json")
  grafana_dashboard_temperatures = file("${path.module}/dashboards/klipper-temperatures.json")
  grafana_dashboard_k8s_cluster  = file("${path.module}/dashboards/k8s-cluster-overview.json")
  grafana_dashboard_k8s_workload = file("${path.module}/dashboards/k8s-workloads.json")
  grafana_dashboard_ping         = file("${path.module}/dashboards/internet-ping.json")
  grafana_dashboard_unifi_client = file("${path.module}/dashboards/unifi-clients.json")
  grafana_dashboard_unifi_ap     = file("${path.module}/dashboards/unifi-uap.json")
}

# Keep the namespace in state so the stack owns the live monitoring domain.
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
  }
}

# Preserve the headless VictoriaMetrics service identity used by vmagent and
# Grafana datasources.
resource "kubernetes_service_v1" "victoria_metrics" {
  wait_for_load_balancer = false

  metadata {
    name      = "victoria-metrics"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    cluster_ip = "None"
    selector = {
      app = "victoria-metrics"
    }

    port {
      name        = "http"
      port        = 8428
      target_port = 8428
      protocol    = "TCP"
    }

    port {
      name        = "influx-udp"
      port        = 8089
      target_port = 8089
      protocol    = "UDP"
    }
  }
}

# Preserve the existing MetalLB-backed listener used by Proxmox metric pushes.
resource "kubernetes_service_v1" "victoria_metrics_external" {
  wait_for_load_balancer = false

  metadata {
    name      = "victoria-metrics-external"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "metallb.universe.tf/ip-allocated-from-pool" = "production-pool"
      "metallb.universe.tf/loadBalancerIPs"        = var.victoria_metrics_external_ip
    }
  }

  spec {
    type = "LoadBalancer"
    selector = {
      app = "victoria-metrics"
    }

    port {
      name        = "http"
      port        = 8428
      target_port = 8428
      protocol    = "TCP"
    }

    port {
      name        = "influx-udp"
      port        = 8089
      target_port = 8089
      protocol    = "UDP"
    }
  }
}

# Match the live single-node VictoriaMetrics stateful workload and its retained
# storage template.
resource "kubernetes_stateful_set_v1" "victoria_metrics" {
  wait_for_rollout = false

  lifecycle {
    ignore_changes = [
      # The Kubernetes provider synthesizes PVC template metadata defaults such
      # as namespace during import, which would otherwise force replacement of
      # the live retained VictoriaMetrics volume template.
      metadata[0].annotations,
      metadata[0].labels,
      spec[0].template[0].metadata[0].annotations,
      spec[0].template[0].spec[0].active_deadline_seconds,
      spec[0].template[0].spec[0].node_selector,
      spec[0].template[0].spec[0].container[0].command,
      spec[0].template[0].spec[0].container[0].termination_message_policy,
      spec[0].template[0].spec[0].container[0].port[0].host_port,
      spec[0].template[0].spec[0].container[0].port[1].host_port,
      spec[0].volume_claim_template[0].metadata[0].annotations,
      spec[0].volume_claim_template[0].metadata[0].labels,
      spec[0].volume_claim_template[0].metadata[0].namespace,
      spec[0].volume_claim_template[0].spec[0].resources[0].limits,
    ]
  }

  metadata {
    name      = "victoria-metrics"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    service_name = kubernetes_service_v1.victoria_metrics.metadata[0].name
    replicas     = 1

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    selector {
      match_labels = {
        app = "victoria-metrics"
      }
    }

    template {
      metadata {
        labels = {
          app = "victoria-metrics"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "victoria-metrics"
          image             = "victoriametrics/victoria-metrics:v1.136.0"
          image_pull_policy = "IfNotPresent"
          args = [
            "-storageDataPath=/storage",
            "-retentionPeriod=1y",
            "-httpListenAddr=:8428",
            "-influxListenAddr=:8089",
          ]

          port {
            container_port = 8428
            name           = "http"
            protocol       = "TCP"
          }

          port {
            container_port = 8089
            name           = "influx-udp"
            protocol       = "UDP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "storage"
            mount_path = "/storage"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "storage"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class_name
        volume_mode        = "Filesystem"

        resources {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
  }
}

# Import the live Helm release instead of recreating kube-state-metrics as raw
# resources, because the release secret still exists and is recoverable.
resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = var.kube_state_metrics_chart_version
}

# Keep the stable service name consumed by vmagent.
resource "kubernetes_service_v1" "snmp_exporter" {
  wait_for_load_balancer = false

  metadata {
    name      = "snmp-exporter"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "snmp-exporter"
    }

    port {
      name        = "http"
      port        = 9116
      target_port = 9116
      protocol    = "TCP"
    }
  }
}

# Preserve the current SNMP exporter deployment that uses the image's bundled
# config and the long-lived ClusterIP service.
resource "kubernetes_deployment_v1" "snmp_exporter" {
  wait_for_rollout = false

  metadata {
    name      = "snmp-exporter"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "snmp-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "snmp-exporter"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "snmp-exporter"
          image             = "prom/snmp-exporter:v0.30.1"
          image_pull_policy = "IfNotPresent"
          args              = ["--config.file=/etc/snmp_exporter/snmp.yml"]

          port {
            container_port = 9116
            name           = "http"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# Preserve the exact blackbox probe config committed from the live ConfigMap.
resource "kubernetes_config_map_v1" "blackbox_exporter" {
  metadata {
    name      = "blackbox-exporter"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "blackbox.yml" = local.blackbox_config
  }
}

# Keep the ClusterIP used by vmagent for ICMP probing.
resource "kubernetes_service_v1" "blackbox_exporter" {
  wait_for_load_balancer = false

  metadata {
    name      = "blackbox-exporter"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "blackbox-exporter"
    }

    port {
      name        = "http"
      port        = 9115
      target_port = 9115
      protocol    = "TCP"
    }
  }
}

# Match the current NET_RAW-enabled blackbox exporter deployment.
resource "kubernetes_deployment_v1" "blackbox_exporter" {
  wait_for_rollout = false

  metadata {
    name      = "blackbox-exporter"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "blackbox-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "blackbox-exporter"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "blackbox-exporter"
          image             = "prom/blackbox-exporter:v0.25.0"
          image_pull_policy = "IfNotPresent"
          args              = ["--config.file=/config/blackbox.yml"]

          port {
            container_port = 9115
            name           = "http"
            protocol       = "TCP"
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false
            run_as_non_root            = false

            capabilities {
              add = ["NET_RAW"]
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.blackbox_exporter.metadata[0].name
          }
        }
      }
    }
  }
}

# Preserve the live Unpoller credentials without writing them back to source.
resource "kubernetes_secret_v1" "unpoller" {
  data_wo_revision               = 1
  wait_for_service_account_token = false

  metadata {
    name      = "unpoller"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data_wo = {
    UP_UNIFI_DEFAULT_USER = var.unpoller_username
    UP_UNIFI_DEFAULT_PASS = var.unpoller_password
  }

  lifecycle {
    ignore_changes = [
      data_wo_revision,
    ]
  }
}

# Keep the stable Unpoller scrape endpoint used by vmagent.
resource "kubernetes_service_v1" "unpoller" {
  wait_for_load_balancer = false

  metadata {
    name      = "unpoller"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "unpoller"
    }

    port {
      name        = "http"
      port        = 9130
      target_port = 9130
      protocol    = "TCP"
    }
  }
}

# Match the current live Unpoller flags, including the disabled DPI export.
resource "kubernetes_deployment_v1" "unpoller" {
  wait_for_rollout = false

  metadata {
    name      = "unpoller"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "unpoller"
      }
    }

    template {
      metadata {
        labels = {
          app = "unpoller"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "unpoller"
          image             = "ghcr.io/unpoller/unpoller:v2.15.4"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 9130
            name           = "http"
            protocol       = "TCP"
          }

          env {
            name  = "UP_INFLUXDB_DISABLE"
            value = "true"
          }

          env {
            name  = "UP_PROMETHEUS_HTTP_LISTEN"
            value = "0.0.0.0:9130"
          }

          env {
            name  = "UP_PROMETHEUS_NAMESPACE"
            value = "unpoller"
          }

          env {
            name  = "UP_UNIFI_DEFAULT_URL"
            value = var.unpoller_unifi_url
          }

          env {
            name = "UP_UNIFI_DEFAULT_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.unpoller.metadata[0].name
                key  = "UP_UNIFI_DEFAULT_USER"
              }
            }
          }

          env {
            name = "UP_UNIFI_DEFAULT_PASS"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.unpoller.metadata[0].name
                key  = "UP_UNIFI_DEFAULT_PASS"
              }
            }
          }

          env {
            name  = "UP_UNIFI_DEFAULT_VERIFY_SSL"
            value = "false"
          }

          env {
            name  = "UP_UNIFI_DEFAULT_SAVE_SITES"
            value = "true"
          }

          env {
            name  = "UP_UNIFI_DEFAULT_SAVE_DPI"
            value = "false"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# Store the imported vmagent scrape config verbatim so the handoff does not
# regenerate the long live target list during the Pulumi retirement.
resource "kubernetes_config_map_v1" "vmagent" {
  metadata {
    name      = "vmagent"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = local.vmagent_scrape_config
  }
}

# Keep the current service account name used by vmagent for API scraping.
resource "kubernetes_service_account_v1" "vmagent" {
  automount_service_account_token = false

  metadata {
    name      = "vmagent"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
}

# Preserve the existing cluster-wide scrape permissions granted to vmagent.
resource "kubernetes_cluster_role_v1" "vmagent_scrape" {
  metadata {
    name = "vmagent-scrape"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

# Bind the scrape ClusterRole to the imported vmagent service account.
resource "kubernetes_cluster_role_binding_v1" "vmagent_scrape" {
  metadata {
    name = "vmagent-scrape"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.vmagent_scrape.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vmagent.metadata[0].name
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
}

# Keep the current vmagent deployment shape and its mounted imported config.
resource "kubernetes_deployment_v1" "vmagent" {
  wait_for_rollout = false

  metadata {
    name      = "vmagent"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vmagent"
      }
    }

    template {
      metadata {
        labels = {
          app = "vmagent"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false
        service_account_name            = kubernetes_service_account_v1.vmagent.metadata[0].name

        container {
          name              = "vmagent"
          image             = "victoriametrics/vmagent:v1.136.0"
          image_pull_policy = "IfNotPresent"
          args = [
            "-promscrape.config=/etc/prometheus/prometheus.yml",
            "-remoteWrite.url=http://victoria-metrics:8428/api/v1/write",
          ]

          port {
            container_port = 8429
            name           = "http"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.vmagent.metadata[0].name
          }
        }
      }
    }
  }
}

# Preserve the existing Grafana PVC so dashboards and local state remain intact.
resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
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

# Commit the current datasource provisioner config that points Grafana at the
# imported VictoriaMetrics service.
resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "datasources.yaml" = local.grafana_datasources
  }
}

# Preserve the current dashboard folder mapping used by the live Grafana pod.
resource "kubernetes_config_map_v1" "grafana_dashboard_providers" {
  metadata {
    name      = "grafana-dashboard-providers"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "dashboardproviders.yaml" = local.grafana_dashboard_providers
  }
}

# Keep the exact live set of non-UniFi dashboards mounted under /dashboards.
resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "internet-ping.json"        = local.grafana_dashboard_ping
    "k8s-cluster-overview.json" = local.grafana_dashboard_k8s_cluster
    "k8s-workloads.json"        = local.grafana_dashboard_k8s_workload
    "klipper-overview.json"     = local.grafana_dashboard_klipper
    "klipper-temperatures.json" = local.grafana_dashboard_temperatures
  }
}

# The live Grafana pod currently mounts only two UniFi dashboards, so model
# that exact subset instead of the larger historical Pulumi source set.
resource "kubernetes_config_map_v1" "grafana_dashboards_unifi" {
  metadata {
    name      = "grafana-dashboards-unifi"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "unifi-clients.json" = local.grafana_dashboard_unifi_client
    "unifi-uap.json"     = local.grafana_dashboard_unifi_ap
  }
}

# Preserve the sidecar renderer deployment used by Grafana alert screenshots.
resource "kubernetes_deployment_v1" "grafana_image_renderer" {
  wait_for_rollout = false

  metadata {
    name      = "grafana-image-renderer"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana-image-renderer"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana-image-renderer"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "image-renderer"
          image             = "grafana/grafana-image-renderer:v5.6.0"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "METRICS_ENABLED"
            value = "true"
          }

          port {
            container_port = 8081
            name           = "http"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}

# Keep the stable renderer service name that Grafana references in env vars.
resource "kubernetes_service_v1" "grafana_image_renderer" {
  wait_for_load_balancer = false

  metadata {
    name      = "grafana-image-renderer"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "grafana-image-renderer"
    }

    port {
      name        = "http"
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
    }
  }
}

# Match the current Grafana deployment, including the simplified dashboard
# mounts that now omit the retired DPI-specific ConfigMap.
resource "kubernetes_deployment_v1" "grafana" {
  wait_for_rollout = false

  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "grafana"
          image             = "grafana/grafana:12.3.3"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "GF_AUTH_ANONYMOUS_ENABLED"
            value = "true"
          }

          env {
            name  = "GF_AUTH_ANONYMOUS_ORG_ROLE"
            value = "Admin"
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }

          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://${var.grafana_hostname}/"
          }

          env {
            name  = "GF_SERVER_DOMAIN"
            value = var.grafana_hostname
          }

          env {
            name  = "GF_RENDERING_SERVER_URL"
            value = "http://${kubernetes_service_v1.grafana_image_renderer.metadata[0].name}:8081/render"
          }

          env {
            name  = "GF_RENDERING_CALLBACK_URL"
            value = "http://${kubernetes_service_v1.grafana.metadata[0].name}:80/"
          }

          env {
            name  = "GF_UNIFIED_ALERTING_SCREENSHOTS_CAPTURE"
            value = "true"
          }

          port {
            container_port = 3000
            name           = "http"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "storage"
            mount_path = "/var/lib/grafana"
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
          }

          volume_mount {
            name       = "dashboard-providers"
            mount_path = "/etc/grafana/provisioning/dashboards"
          }

          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana/dashboards"
          }

          volume_mount {
            name       = "dashboards-unifi"
            mount_path = "/var/lib/grafana/dashboards/unifi"
          }
        }

        volume {
          name = "storage"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.grafana.metadata[0].name
          }
        }

        volume {
          name = "datasources"

          config_map {
            name = kubernetes_config_map_v1.grafana_datasources.metadata[0].name
          }
        }

        volume {
          name = "dashboard-providers"

          config_map {
            name = kubernetes_config_map_v1.grafana_dashboard_providers.metadata[0].name
          }
        }

        volume {
          name = "dashboards"

          config_map {
            name = kubernetes_config_map_v1.grafana_dashboards.metadata[0].name

            items {
              key  = "klipper-overview.json"
              path = "klipper/klipper-overview.json"
            }

            items {
              key  = "klipper-temperatures.json"
              path = "klipper/klipper-temperatures.json"
            }

            items {
              key  = "k8s-cluster-overview.json"
              path = "k8s/k8s-cluster-overview.json"
            }

            items {
              key  = "k8s-workloads.json"
              path = "k8s/k8s-workloads.json"
            }

            items {
              key  = "internet-ping.json"
              path = "network/internet-ping.json"
            }
          }
        }

        volume {
          name = "dashboards-unifi"

          config_map {
            name = kubernetes_config_map_v1.grafana_dashboards_unifi.metadata[0].name
          }
        }
      }
    }
  }
}

# Keep the stable internal Grafana service referenced by the ingress.
resource "kubernetes_service_v1" "grafana" {
  wait_for_load_balancer = false

  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }
  }
}

# Preserve the live Traefik ingress and its cert-manager annotation.
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [var.grafana_hostname]
      secret_name = "grafana-tls"
    }

    rule {
      host = var.grafana_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.grafana.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
