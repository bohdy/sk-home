# Describe the adopted cluster-core inputs explicitly so the shared platform
# stack stays reviewable and does not hide live defaults in resource bodies.
variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for the k3s cluster."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used by cert-manager DNS01 issuers."
  type        = string
  sensitive   = true
}

variable "email" {
  description = "ACME registration email for cluster issuers."
  type        = string
}

variable "metallb_chart_version" {
  description = "Pinned MetalLB Helm chart version."
  type        = string
  default     = "0.14.8"
}

variable "metallb_ip_pool_addresses" {
  description = "Address ranges advertised by the live MetalLB IPAddressPool."
  type        = list(string)
  default     = ["10.1.30.0/24"]
}

variable "metallb_my_asn" {
  description = "Local ASN used by the live MetalLB BGP peer."
  type        = number
  default     = 65001
}

variable "metallb_peer_asn" {
  description = "Remote ASN used by the live MetalLB BGP peer."
  type        = number
  default     = 65001
}

variable "metallb_peer_address" {
  description = "Gateway address used by the live MetalLB BGP peer."
  type        = string
  default     = "10.1.20.1"
}

variable "nfs_chart_version" {
  description = "Pinned NFS external provisioner chart version."
  type        = string
  default     = "4.0.18"
}

variable "nfs_release_name" {
  description = "Existing Helm release name for the NFS subdir external provisioner."
  type        = string
  default     = "nfs-provisioner-release-d00da357"
}

variable "nfs_server" {
  description = "NFS server backing the default storage class."
  type        = string
  default     = "10.1.100.10"
}

variable "nfs_path" {
  description = "NFS export path backing the default storage class."
  type        = string
  default     = "/volume1/k3s-storage"
}

variable "storage_class_name" {
  description = "Default storage class name exposed by the NFS provisioner."
  type        = string
  default     = "synology-nfs"
}

variable "cert_manager_chart_version" {
  description = "Pinned cert-manager Helm chart version."
  type        = string
  default     = "1.20.1"
}

variable "cert_manager_cloudflare_secret_name" {
  description = "Cloudflare API token secret name used by cert-manager."
  type        = string
  default     = "cert-manager-cf-secret-a326168a"
}

variable "traefik_chart_version" {
  description = "Pinned Traefik chart version."
  type        = string
  default     = "38.0.1"
}

variable "traefik_dashboard_hostname" {
  description = "Public hostname of the Traefik dashboard route."
  type        = string
  default     = "traefik.sk.bohdal.name"
}

variable "enable_crd_manifests" {
  description = "Whether to manage CRD-backed Kubernetes manifests in this stack. Disable only for initial bootstrap before Helm installs CRDs."
  type        = bool
  default     = true
}

variable "manage_coredns_config" {
  description = "Whether this stack should manage the kube-system coredns ConfigMap. Keep disabled when the cluster already owns this object."
  type        = bool
  default     = false
}
