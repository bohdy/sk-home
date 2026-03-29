locals {
  # Mirror the live cert-manager control-plane objects exactly enough for a
  # clean import-first handoff. The original Pulumi chart left Helm-style
  # labels behind but no recoverable Helm release record, so direct resource
  # ownership is the only safe source-of-truth path here.
  cert_manager_service_accounts = {
    "cert-manager-chart" = {
      annotations = {}
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
    }
    "cert-manager-chart-cainjector" = {
      annotations = {}
      labels = {
        app                            = "cainjector"
        "app.kubernetes.io/component"  = "cainjector"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cainjector"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
    }
    "cert-manager-chart-startupapicheck" = {
      annotations = {
        "helm.sh/hook"               = "post-install"
        "helm.sh/hook-delete-policy" = "before-hook-creation,hook-succeeded"
        "helm.sh/hook-weight"        = "-5"
      }
      labels = {
        app                            = "startupapicheck"
        "app.kubernetes.io/component"  = "startupapicheck"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "startupapicheck"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
    }
    "cert-manager-chart-webhook" = {
      annotations = {}
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
    }
  }

  cert_manager_services = {
    "cert-manager-chart" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      spec = {
        clusterIP             = "10.106.241.248"
        clusterIPs            = ["10.106.241.248"]
        internalTrafficPolicy = "Cluster"
        ipFamilies            = ["IPv4"]
        ipFamilyPolicy        = "SingleStack"
        ports = [
          {
            name       = "tcp-prometheus-servicemonitor"
            port       = 9402
            protocol   = "TCP"
            targetPort = 9402
          }
        ]
        selector = {
          "app.kubernetes.io/component" = "controller"
          "app.kubernetes.io/instance"  = "cert-manager-chart"
          "app.kubernetes.io/name"      = "cert-manager"
        }
        sessionAffinity = "None"
        type            = "ClusterIP"
      }
    }
    "cert-manager-chart-webhook" = {
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      spec = {
        clusterIP             = "10.102.49.199"
        clusterIPs            = ["10.102.49.199"]
        internalTrafficPolicy = "Cluster"
        ipFamilies            = ["IPv4"]
        ipFamilyPolicy        = "SingleStack"
        ports = [
          {
            name       = "https"
            port       = 443
            protocol   = "TCP"
            targetPort = "https"
          }
        ]
        selector = {
          "app.kubernetes.io/component" = "webhook"
          "app.kubernetes.io/instance"  = "cert-manager-chart"
          "app.kubernetes.io/name"      = "webhook"
        }
        sessionAffinity = "None"
        type            = "ClusterIP"
      }
    }
  }

  cert_manager_roles = {
    "cert-manager-chart-startupapicheck:create-cert" = {
      annotations = {
        "helm.sh/hook"               = "post-install"
        "helm.sh/hook-delete-policy" = "before-hook-creation,hook-succeeded"
        "helm.sh/hook-weight"        = "-5"
      }
      labels = {
        app                            = "startupapicheck"
        "app.kubernetes.io/component"  = "startupapicheck"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "startupapicheck"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates"]
          verbs     = ["create"]
        }
      ]
    }
    "cert-manager-chart-webhook:dynamic-serving" = {
      annotations = {}
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups     = [""]
          resourceNames = ["cert-manager-chart-webhook-ca"]
          resources     = ["secrets"]
          verbs         = ["get", "list", "watch", "update"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["create"]
        }
      ]
    }
  }

  cert_manager_role_bindings = {
    "cert-manager-chart-startupapicheck:create-cert" = {
      annotations = {
        "helm.sh/hook"               = "post-install"
        "helm.sh/hook-delete-policy" = "before-hook-creation,hook-succeeded"
        "helm.sh/hook-weight"        = "-5"
      }
      labels = {
        app                            = "startupapicheck"
        "app.kubernetes.io/component"  = "startupapicheck"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "startupapicheck"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "Role"
        name     = "cert-manager-chart-startupapicheck:create-cert"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart-startupapicheck"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-webhook:dynamic-serving" = {
      annotations = {}
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "Role"
        name     = "cert-manager-chart-webhook:dynamic-serving"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart-webhook"
          namespace = "cert-manager"
        }
      ]
    }
  }

  cert_manager_cluster_roles = {
    "cert-manager-chart-cainjector" = {
      labels = {
        app                            = "cainjector"
        "app.kubernetes.io/component"  = "cainjector"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cainjector"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["get", "create", "update", "patch"]
        },
        {
          apiGroups = ["admissionregistration.k8s.io"]
          resources = ["validatingwebhookconfigurations", "mutatingwebhookconfigurations"]
          verbs     = ["get", "list", "watch", "update", "patch"]
        },
        {
          apiGroups = ["apiregistration.k8s.io"]
          resources = ["apiservices"]
          verbs     = ["get", "list", "watch", "update", "patch"]
        },
        {
          apiGroups = ["apiextensions.k8s.io"]
          resources = ["customresourcedefinitions"]
          verbs     = ["get", "list", "watch", "update", "patch"]
        }
      ]
    }
    "cert-manager-chart-cluster-view" = {
      labels = {
        app                                                     = "cert-manager"
        "app.kubernetes.io/component"                           = "controller"
        "app.kubernetes.io/instance"                            = "cert-manager-chart"
        "app.kubernetes.io/managed-by"                          = "Helm"
        "app.kubernetes.io/name"                                = "cert-manager"
        "app.kubernetes.io/version"                             = "v1.14.4"
        "helm.sh/chart"                                         = "cert-manager-v1.14.4"
        "rbac.authorization.k8s.io/aggregate-to-cluster-reader" = "true"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["clusterissuers"]
          verbs     = ["get", "list", "watch"]
        }
      ]
    }
    "cert-manager-chart-controller-approve:cert-manager-io" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "cert-manager"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups     = ["cert-manager.io"]
          resourceNames = ["issuers.cert-manager.io/*", "clusterissuers.cert-manager.io/*"]
          resources     = ["signers"]
          verbs         = ["approve"]
        }
      ]
    }
    "cert-manager-chart-controller-certificates" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificates/status", "certificaterequests", "certificaterequests/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificaterequests", "clusterissuers", "issuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates/finalizers", "certificaterequests/finalizers"]
          verbs     = ["update"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["orders"]
          verbs     = ["create", "delete", "get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch", "create", "update", "delete", "patch"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        }
      ]
    }
    "cert-manager-chart-controller-certificatesigningrequests" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "cert-manager"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["certificates.k8s.io"]
          resources = ["certificatesigningrequests"]
          verbs     = ["get", "list", "watch", "update"]
        },
        {
          apiGroups = ["certificates.k8s.io"]
          resources = ["certificatesigningrequests/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups     = ["certificates.k8s.io"]
          resourceNames = ["issuers.cert-manager.io/*", "clusterissuers.cert-manager.io/*"]
          resources     = ["signers"]
          verbs         = ["sign"]
        },
        {
          apiGroups = ["authorization.k8s.io"]
          resources = ["subjectaccessreviews"]
          verbs     = ["create"]
        }
      ]
    }
    "cert-manager-chart-controller-challenges" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges", "challenges/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["issuers", "clusterissuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        },
        {
          apiGroups = [""]
          resources = ["pods", "services"]
          verbs     = ["get", "list", "watch", "create", "delete"]
        },
        {
          apiGroups = ["networking.k8s.io"]
          resources = ["ingresses"]
          verbs     = ["get", "list", "watch", "create", "delete", "update"]
        },
        {
          apiGroups = ["gateway.networking.k8s.io"]
          resources = ["httproutes"]
          verbs     = ["get", "list", "watch", "create", "delete", "update"]
        },
        {
          apiGroups = ["route.openshift.io"]
          resources = ["routes/custom-host"]
          verbs     = ["create"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges/finalizers"]
          verbs     = ["update"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch"]
        }
      ]
    }
    "cert-manager-chart-controller-clusterissuers" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["clusterissuers", "clusterissuers/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["clusterissuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch", "create", "update", "delete"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        }
      ]
    }
    "cert-manager-chart-controller-ingress-shim" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificaterequests"]
          verbs     = ["create", "update", "delete"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificaterequests", "issuers", "clusterissuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["networking.k8s.io"]
          resources = ["ingresses"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["networking.k8s.io"]
          resources = ["ingresses/finalizers"]
          verbs     = ["update"]
        },
        {
          apiGroups = ["gateway.networking.k8s.io"]
          resources = ["gateways", "httproutes"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["gateway.networking.k8s.io"]
          resources = ["gateways/finalizers", "httproutes/finalizers"]
          verbs     = ["update"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        }
      ]
    }
    "cert-manager-chart-controller-issuers" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["issuers", "issuers/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["issuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch", "create", "update", "delete"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        }
      ]
    }
    "cert-manager-chart-controller-orders" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["orders", "orders/status"]
          verbs     = ["update", "patch"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["orders", "challenges"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["clusterissuers", "issuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges"]
          verbs     = ["create", "delete"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["orders/finalizers"]
          verbs     = ["update"]
        },
        {
          apiGroups = [""]
          resources = ["secrets"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = [""]
          resources = ["events"]
          verbs     = ["create", "patch"]
        }
      ]
    }
    "cert-manager-chart-edit" = {
      labels = {
        app                                            = "cert-manager"
        "app.kubernetes.io/component"                  = "controller"
        "app.kubernetes.io/instance"                   = "cert-manager-chart"
        "app.kubernetes.io/managed-by"                 = "Helm"
        "app.kubernetes.io/name"                       = "cert-manager"
        "app.kubernetes.io/version"                    = "v1.14.4"
        "helm.sh/chart"                                = "cert-manager-v1.14.4"
        "rbac.authorization.k8s.io/aggregate-to-admin" = "true"
        "rbac.authorization.k8s.io/aggregate-to-edit"  = "true"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificaterequests", "issuers"]
          verbs     = ["create", "delete", "deletecollection", "patch", "update"]
        },
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates/status"]
          verbs     = ["update"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges", "orders"]
          verbs     = ["create", "delete", "deletecollection", "patch", "update"]
        }
      ]
    }
    "cert-manager-chart-view" = {
      labels = {
        app                                                     = "cert-manager"
        "app.kubernetes.io/component"                           = "controller"
        "app.kubernetes.io/instance"                            = "cert-manager-chart"
        "app.kubernetes.io/managed-by"                          = "Helm"
        "app.kubernetes.io/name"                                = "cert-manager"
        "app.kubernetes.io/version"                             = "v1.14.4"
        "helm.sh/chart"                                         = "cert-manager-v1.14.4"
        "rbac.authorization.k8s.io/aggregate-to-admin"          = "true"
        "rbac.authorization.k8s.io/aggregate-to-cluster-reader" = "true"
        "rbac.authorization.k8s.io/aggregate-to-edit"           = "true"
        "rbac.authorization.k8s.io/aggregate-to-view"           = "true"
      }
      rules = [
        {
          apiGroups = ["cert-manager.io"]
          resources = ["certificates", "certificaterequests", "issuers"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["acme.cert-manager.io"]
          resources = ["challenges", "orders"]
          verbs     = ["get", "list", "watch"]
        }
      ]
    }
    "cert-manager-chart-webhook:subjectaccessreviews" = {
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      rules = [
        {
          apiGroups = ["authorization.k8s.io"]
          resources = ["subjectaccessreviews"]
          verbs     = ["create"]
        }
      ]
    }
  }

  cert_manager_cluster_role_bindings = {
    "cert-manager-chart-cainjector" = {
      labels = {
        app                            = "cainjector"
        "app.kubernetes.io/component"  = "cainjector"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cainjector"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-cainjector"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart-cainjector"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-approve:cert-manager-io" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "cert-manager"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-approve:cert-manager-io"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-certificates" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-certificates"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-certificatesigningrequests" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "cert-manager"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-certificatesigningrequests"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-challenges" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-challenges"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-clusterissuers" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-clusterissuers"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-ingress-shim" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-ingress-shim"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-issuers" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-issuers"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-controller-orders" = {
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-controller-orders"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart"
          namespace = "cert-manager"
        }
      ]
    }
    "cert-manager-chart-webhook:subjectaccessreviews" = {
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      role_ref = {
        apiGroup = "rbac.authorization.k8s.io"
        kind     = "ClusterRole"
        name     = "cert-manager-chart-webhook:subjectaccessreviews"
      }
      subjects = [
        {
          kind      = "ServiceAccount"
          name      = "cert-manager-chart-webhook"
          namespace = "cert-manager"
        }
      ]
    }
  }

  cert_manager_deployments = {
    "cert-manager-chart" = {
      annotations = {
        "pulumi.com/patchForce" = "true"
      }
      labels = {
        app                            = "cert-manager"
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cert-manager"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      spec = {
        progressDeadlineSeconds = 600
        replicas                = 1
        revisionHistoryLimit    = 10
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "controller"
            "app.kubernetes.io/instance"  = "cert-manager-chart"
            "app.kubernetes.io/name"      = "cert-manager"
          }
        }
        strategy = {
          rollingUpdate = {
            maxSurge       = "25%"
            maxUnavailable = "25%"
          }
          type = "RollingUpdate"
        }
        template = {
          metadata = {
            annotations = {
              "kubectl.kubernetes.io/restartedAt" = "2026-02-19T22:03:42+01:00"
              "prometheus.io/path"                = "/metrics"
              "prometheus.io/port"                = "9402"
              "prometheus.io/scrape"              = "true"
            }
            labels = {
              app                            = "cert-manager"
              "app.kubernetes.io/component"  = "controller"
              "app.kubernetes.io/instance"   = "cert-manager-chart"
              "app.kubernetes.io/managed-by" = "Helm"
              "app.kubernetes.io/name"       = "cert-manager"
              "app.kubernetes.io/version"    = "v1.14.4"
              "helm.sh/chart"                = "cert-manager-v1.14.4"
            }
          }
          spec = {
            containers = [
              {
                args = [
                  "--v=2",
                  "--cluster-resource-namespace=$(POD_NAMESPACE)",
                  "--leader-election-namespace=kube-system",
                  "--acme-http01-solver-image=quay.io/jetstack/cert-manager-acmesolver:v1.14.4",
                  "--max-concurrent-challenges=60",
                ]
                env = [
                  {
                    name = "POD_NAMESPACE"
                    valueFrom = {
                      fieldRef = {
                        apiVersion = "v1"
                        fieldPath  = "metadata.namespace"
                      }
                    }
                  }
                ]
                image           = "quay.io/jetstack/cert-manager-controller:v1.14.4"
                imagePullPolicy = "IfNotPresent"
                livenessProbe = {
                  failureThreshold = 8
                  httpGet = {
                    path   = "/livez"
                    port   = "http-healthz"
                    scheme = "HTTP"
                  }
                  initialDelaySeconds = 10
                  periodSeconds       = 10
                  successThreshold    = 1
                  timeoutSeconds      = 15
                }
                name = "cert-manager-controller"
                ports = [
                  {
                    containerPort = 9402
                    name          = "http-metrics"
                    protocol      = "TCP"
                  },
                  {
                    containerPort = 9403
                    name          = "http-healthz"
                    protocol      = "TCP"
                  }
                ]
                resources = {}
                securityContext = {
                  allowPrivilegeEscalation = false
                  capabilities = {
                    drop = ["ALL"]
                  }
                  readOnlyRootFilesystem = true
                }
                terminationMessagePath   = "/dev/termination-log"
                terminationMessagePolicy = "File"
              }
            ]
            dnsConfig = {
              nameservers = ["86.54.11.1", "1.1.1.1"]
              options = [
                {
                  name  = "ndots"
                  value = "1"
                }
              ]
            }
            dnsPolicy          = "None"
            enableServiceLinks = false
            nodeSelector = {
              "kubernetes.io/hostname" = "k8s-worker-2"
            }
            restartPolicy = "Always"
            schedulerName = "default-scheduler"
            securityContext = {
              runAsNonRoot = true
              seccompProfile = {
                type = "RuntimeDefault"
              }
            }
            serviceAccount                = "cert-manager-chart"
            serviceAccountName            = "cert-manager-chart"
            terminationGracePeriodSeconds = 30
          }
        }
      }
    }
    "cert-manager-chart-cainjector" = {
      annotations = {}
      labels = {
        app                            = "cainjector"
        "app.kubernetes.io/component"  = "cainjector"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "cainjector"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      spec = {
        progressDeadlineSeconds = 600
        replicas                = 1
        revisionHistoryLimit    = 10
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "cainjector"
            "app.kubernetes.io/instance"  = "cert-manager-chart"
            "app.kubernetes.io/name"      = "cainjector"
          }
        }
        strategy = {
          rollingUpdate = {
            maxSurge       = "25%"
            maxUnavailable = "25%"
          }
          type = "RollingUpdate"
        }
        template = {
          metadata = {
            labels = {
              app                            = "cainjector"
              "app.kubernetes.io/component"  = "cainjector"
              "app.kubernetes.io/instance"   = "cert-manager-chart"
              "app.kubernetes.io/managed-by" = "Helm"
              "app.kubernetes.io/name"       = "cainjector"
              "app.kubernetes.io/version"    = "v1.14.4"
              "helm.sh/chart"                = "cert-manager-v1.14.4"
            }
          }
          spec = {
            containers = [
              {
                args = [
                  "--v=2",
                  "--leader-election-namespace=kube-system",
                ]
                env = [
                  {
                    name = "POD_NAMESPACE"
                    valueFrom = {
                      fieldRef = {
                        apiVersion = "v1"
                        fieldPath  = "metadata.namespace"
                      }
                    }
                  }
                ]
                image           = "quay.io/jetstack/cert-manager-cainjector:v1.14.4"
                imagePullPolicy = "IfNotPresent"
                name            = "cert-manager-cainjector"
                resources       = {}
                securityContext = {
                  allowPrivilegeEscalation = false
                  capabilities = {
                    drop = ["ALL"]
                  }
                  readOnlyRootFilesystem = true
                }
                terminationMessagePath   = "/dev/termination-log"
                terminationMessagePolicy = "File"
              }
            ]
            dnsPolicy          = "ClusterFirst"
            enableServiceLinks = false
            nodeSelector = {
              "kubernetes.io/os" = "linux"
            }
            restartPolicy = "Always"
            schedulerName = "default-scheduler"
            securityContext = {
              runAsNonRoot = true
              seccompProfile = {
                type = "RuntimeDefault"
              }
            }
            serviceAccount                = "cert-manager-chart-cainjector"
            serviceAccountName            = "cert-manager-chart-cainjector"
            terminationGracePeriodSeconds = 30
          }
        }
      }
    }
    "cert-manager-chart-webhook" = {
      annotations = {
        "pulumi.com/patchForce" = "true"
      }
      labels = {
        app                            = "webhook"
        "app.kubernetes.io/component"  = "webhook"
        "app.kubernetes.io/instance"   = "cert-manager-chart"
        "app.kubernetes.io/managed-by" = "Helm"
        "app.kubernetes.io/name"       = "webhook"
        "app.kubernetes.io/version"    = "v1.14.4"
        "helm.sh/chart"                = "cert-manager-v1.14.4"
      }
      spec = {
        progressDeadlineSeconds = 600
        replicas                = 1
        revisionHistoryLimit    = 10
        selector = {
          matchLabels = {
            "app.kubernetes.io/component" = "webhook"
            "app.kubernetes.io/instance"  = "cert-manager-chart"
            "app.kubernetes.io/name"      = "webhook"
          }
        }
        strategy = {
          rollingUpdate = {
            maxSurge       = "25%"
            maxUnavailable = "25%"
          }
          type = "RollingUpdate"
        }
        template = {
          metadata = {
            annotations = {
              "kubectl.kubernetes.io/restartedAt" = "2026-02-19T22:03:42+01:00"
            }
            labels = {
              app                            = "webhook"
              "app.kubernetes.io/component"  = "webhook"
              "app.kubernetes.io/instance"   = "cert-manager-chart"
              "app.kubernetes.io/managed-by" = "Helm"
              "app.kubernetes.io/name"       = "webhook"
              "app.kubernetes.io/version"    = "v1.14.4"
              "helm.sh/chart"                = "cert-manager-v1.14.4"
            }
          }
          spec = {
            containers = [
              {
                args = [
                  "--v=2",
                  "--secure-port=10250",
                  "--dynamic-serving-ca-secret-namespace=$(POD_NAMESPACE)",
                  "--dynamic-serving-ca-secret-name=cert-manager-chart-webhook-ca",
                  "--dynamic-serving-dns-names=cert-manager-chart-webhook",
                  "--dynamic-serving-dns-names=cert-manager-chart-webhook.$(POD_NAMESPACE)",
                  "--dynamic-serving-dns-names=cert-manager-chart-webhook.$(POD_NAMESPACE).svc",
                ]
                env = [
                  {
                    name = "POD_NAMESPACE"
                    valueFrom = {
                      fieldRef = {
                        apiVersion = "v1"
                        fieldPath  = "metadata.namespace"
                      }
                    }
                  }
                ]
                image           = "quay.io/jetstack/cert-manager-webhook:v1.14.4"
                imagePullPolicy = "IfNotPresent"
                livenessProbe = {
                  failureThreshold = 3
                  httpGet = {
                    path   = "/livez"
                    port   = 6080
                    scheme = "HTTP"
                  }
                  initialDelaySeconds = 60
                  periodSeconds       = 10
                  successThreshold    = 1
                  timeoutSeconds      = 1
                }
                name = "cert-manager-webhook"
                ports = [
                  {
                    containerPort = 10250
                    name          = "https"
                    protocol      = "TCP"
                  },
                  {
                    containerPort = 6080
                    name          = "healthcheck"
                    protocol      = "TCP"
                  }
                ]
                readinessProbe = {
                  failureThreshold = 3
                  httpGet = {
                    path   = "/healthz"
                    port   = 6080
                    scheme = "HTTP"
                  }
                  initialDelaySeconds = 5
                  periodSeconds       = 5
                  successThreshold    = 1
                  timeoutSeconds      = 1
                }
                resources = {}
                securityContext = {
                  allowPrivilegeEscalation = false
                  capabilities = {
                    drop = ["ALL"]
                  }
                  readOnlyRootFilesystem = true
                }
                terminationMessagePath   = "/dev/termination-log"
                terminationMessagePolicy = "File"
              }
            ]
            dnsPolicy          = "ClusterFirst"
            enableServiceLinks = false
            nodeSelector = {
              "kubernetes.io/hostname" = "k8s-worker-1"
            }
            restartPolicy = "Always"
            schedulerName = "default-scheduler"
            securityContext = {
              runAsNonRoot = true
              seccompProfile = {
                type = "RuntimeDefault"
              }
            }
            serviceAccount                = "cert-manager-chart-webhook"
            serviceAccountName            = "cert-manager-chart-webhook"
            terminationGracePeriodSeconds = 30
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "cert_manager_service_accounts" {
  for_each = local.cert_manager_service_accounts

  manifest = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = merge(
      {
        name      = each.key
        namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
        labels    = each.value.labels
      },
      length(each.value.annotations) == 0 ? {} : { annotations = each.value.annotations }
    )
    automountServiceAccountToken = true
  }

  depends_on = [kubernetes_namespace_v1.cert_manager]
}

resource "kubernetes_manifest" "cert_manager_services" {
  for_each = local.cert_manager_services

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
      labels    = each.value.labels
    }
    spec = each.value.spec
  }

  depends_on = [kubernetes_namespace_v1.cert_manager]
}

resource "kubernetes_manifest" "cert_manager_roles" {
  for_each = local.cert_manager_roles

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = merge(
      {
        name      = each.key
        namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
        labels    = each.value.labels
      },
      length(each.value.annotations) == 0 ? {} : { annotations = each.value.annotations }
    )
    rules = each.value.rules
  }

  depends_on = [kubernetes_namespace_v1.cert_manager]
}

resource "kubernetes_manifest" "cert_manager_role_bindings" {
  for_each = local.cert_manager_role_bindings

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = merge(
      {
        name      = each.key
        namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
        labels    = each.value.labels
      },
      length(each.value.annotations) == 0 ? {} : { annotations = each.value.annotations }
    )
    roleRef  = each.value.role_ref
    subjects = each.value.subjects
  }

  depends_on = [
    kubernetes_manifest.cert_manager_service_accounts,
    kubernetes_manifest.cert_manager_roles,
  ]
}

resource "kubernetes_manifest" "cert_manager_cluster_roles" {
  for_each = local.cert_manager_cluster_roles

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name   = each.key
      labels = each.value.labels
    }
    rules = each.value.rules
  }
}

resource "kubernetes_manifest" "cert_manager_cluster_role_bindings" {
  for_each = local.cert_manager_cluster_role_bindings

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name   = each.key
      labels = each.value.labels
    }
    roleRef  = each.value.role_ref
    subjects = each.value.subjects
  }

  depends_on = [
    kubernetes_manifest.cert_manager_service_accounts,
    kubernetes_manifest.cert_manager_cluster_roles,
  ]
}

resource "kubernetes_manifest" "cert_manager_deployments" {
  for_each = local.cert_manager_deployments

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = merge(
      {
        name      = each.key
        namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
        labels    = each.value.labels
      },
      length(each.value.annotations) == 0 ? {} : { annotations = each.value.annotations }
    )
    spec = each.value.spec
  }

  depends_on = [
    kubernetes_manifest.cert_manager_service_accounts,
    kubernetes_manifest.cert_manager_role_bindings,
    kubernetes_manifest.cert_manager_cluster_role_bindings,
  ]
}
