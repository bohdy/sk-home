locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      stack       = "cluster-core"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  coredns_corefile = <<-EOT
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
        }
        hosts /etc/coredns/NodeHosts {
          ttl 60
          reload 15s
          fallthrough
        }
        prometheus :9153
        forward . 86.54.11.1 1.1.1.1
        cache 30
        loop
        reload
        loadbalance
        import /etc/coredns/custom/*.override
    }
    import /etc/coredns/custom/*.server
  EOT
}

resource "kubernetes_namespace_v1" "metallb_system" {
  metadata {
    name = "metallb-system"
  }
}

resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = var.metallb_chart_version
  namespace  = kubernetes_namespace_v1.metallb_system.metadata[0].name

  values = [yamlencode({
    speaker = {
      enabled = true
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }
  })]
}

resource "kubernetes_manifest" "metallb_ip_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "production-pool"
      namespace = kubernetes_namespace_v1.metallb_system.metadata[0].name
    }
    spec = {
      addresses = var.metallb_ip_pool_addresses
    }
  }

  depends_on = [helm_release.metallb]
}

resource "kubernetes_manifest" "metallb_bgp_peer" {
  manifest = {
    apiVersion = "metallb.io/v1beta2"
    kind       = "BGPPeer"
    metadata = {
      name      = "router-peer"
      namespace = kubernetes_namespace_v1.metallb_system.metadata[0].name
    }
    spec = {
      myASN       = var.metallb_my_asn
      peerASN     = var.metallb_peer_asn
      peerAddress = var.metallb_peer_address
    }
  }

  depends_on = [helm_release.metallb]
}

resource "kubernetes_manifest" "metallb_bgp_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "BGPAdvertisement"
    metadata = {
      name      = "bgp-advert"
      namespace = kubernetes_namespace_v1.metallb_system.metadata[0].name
    }
    spec = {
      ipAddressPools = ["production-pool"]
    }
  }

  depends_on = [
    kubernetes_manifest.metallb_ip_pool,
    kubernetes_manifest.metallb_bgp_peer,
  ]
}

resource "helm_release" "nfs_subdir_external_provisioner" {
  name       = var.nfs_release_name
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  version    = var.nfs_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    nfs = {
      server = var.nfs_server
      path   = var.nfs_path
    }
    storageClass = {
      defaultClass  = true
      name          = var.storage_class_name
      reclaimPolicy = "Retain"
    }
  })]
}

resource "kubernetes_config_map_v1" "coredns" {
  metadata {
    name      = "coredns"
    namespace = "kube-system"
    annotations = {
      "terraform.sk-home/imported" = "true"
    }
  }

  data = {
    Corefile = local.coredns_corefile
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name       = var.cert_manager_release_name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name

  values = [yamlencode({
    installCRDs = true
  })]
}

resource "kubernetes_secret_v1" "cert_manager_cloudflare" {
  data_wo_revision = 1

  metadata {
    name      = var.cert_manager_cloudflare_secret_name
    namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  }

  data_wo = {
    api-token = var.cloudflare_api_token
  }
}

resource "kubernetes_manifest" "cluster_issuer_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                email = var.email
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cert_manager_cloudflare.metadata[0].name
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.cert_manager_cloudflare,
  ]
}

resource "kubernetes_manifest" "cluster_issuer_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        email  = var.email
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-staging-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                email = var.email
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cert_manager_cloudflare.metadata[0].name
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.cert_manager_cloudflare,
  ]
}

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name

  values = [yamlencode({
    api = {
      dashboard = true
      insecure  = true
    }
    providers = {
      kubernetesCRD = {
        enabled = true
      }
    }
    additionalArguments = [
      "--entryPoints.web.http.redirections.entryPoint.to=websecure",
      "--entryPoints.web.http.redirections.entryPoint.scheme=https",
    ]
    service = {
      type = "LoadBalancer"
    }
    ports = {
      web = {
        expose = { "true" = {} }
        port   = 8000
      }
      websecure = {
        expose = { "true" = {} }
        port   = 8443
        tls = {
          enabled = true
        }
      }
      dns-tcp = {
        expose      = { "true" = {} }
        port        = 55553
        protocol    = "TCP"
        exposedPort = 53
      }
      dns-udp = {
        expose      = { "true" = {} }
        port        = 55553
        protocol    = "UDP"
        exposedPort = 53
      }
    }
    ingressRoute = {
      dashboard = {
        enabled = false
      }
    }
  })]

  depends_on = [kubernetes_manifest.metallb_bgp_advertisement]
}

resource "kubernetes_manifest" "traefik_dashboard_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-dashboard-cert"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      secretName = "traefik-dashboard-tls"
      dnsNames   = [var.traefik_dashboard_hostname]
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
    }
  }

  depends_on = [kubernetes_manifest.cluster_issuer_prod]
}

resource "kubernetes_manifest" "traefik_dashboard_route" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "dashboard"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`${var.traefik_dashboard_hostname}`)"
          kind  = "Rule"
          services = [
            {
              name = "api@internal"
              kind = "TraefikService"
            }
          ]
        }
      ]
      tls = {
        secretName = "traefik-dashboard-tls"
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_manifest.traefik_dashboard_certificate,
  ]
}
