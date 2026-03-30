# Keep the UniFi stack inputs explicit so live resource configuration stays
# reviewable and secrets stay out of committed files.
variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for the existing cluster."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used for the UniFi DNS and Access resources."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for the UniFi Access application."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the UniFi hostname."
  type        = string
}

variable "cloudflare_tunnel_id" {
  description = "Tunnel ID exposed by the migrated identity-edge stack."
  type        = string
}

variable "shared_access_policy_id" {
  description = "Access policy ID exposed by the migrated identity-edge stack."
  type        = string
}

variable "mongo_root_password" {
  description = "MongoDB root password for the live UniFi deployment."
  type        = string
  sensitive   = true
}

variable "namespace_name" {
  description = "Namespace that owns the UniFi workload."
  type        = string
  default     = "unifi"
}

variable "storage_class_name" {
  description = "Storage class used by the existing UniFi PVCs."
  type        = string
  default     = "synology-nfs"
}

variable "domain" {
  description = "Public hostname exposed for the UniFi GUI."
  type        = string
  default     = "unifi.bohdal.name"
}

variable "cluster_issuer_name" {
  description = "Cluster issuer name used for the GUI certificate."
  type        = string
  default     = "letsencrypt-prod"
}

variable "mongo_secret_name" {
  description = "MongoDB secret name for the UniFi stack."
  type        = string
  default     = "unifi-mongo-secret-289546e9"
}

variable "mongo_pvc_name" {
  description = "MongoDB PVC name for the UniFi stack."
  type        = string
  default     = "unifi-mongo-pvc-744244de"
}

variable "mongo_deployment_name" {
  description = "MongoDB deployment name for the UniFi stack."
  type        = string
  default     = "unifi-mongo-dfddd9cd"
}

variable "unifi_pvc_name" {
  description = "UniFi application PVC name."
  type        = string
  default     = "unifi-pvc-e34a12e0"
}

variable "unifi_deployment_name" {
  description = "UniFi application deployment name."
  type        = string
  default     = "unifi-5a072c7e"
}

variable "unifi_pod_annotations" {
  description = "Current pod template annotations on the live UniFi deployment."
  type        = map(string)
  default = {
    "kubectl.kubernetes.io/restartedAt" = "2026-01-07T23:58:40+01:00"
  }
}
