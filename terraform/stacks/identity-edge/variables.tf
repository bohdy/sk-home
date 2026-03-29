# Identify the overall project this stack belongs to.
variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

# Track the target environment without duplicating stack code.
variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

# Capture the Cloudflare account or zone context for access configuration.
variable "access_domain" {
  description = "Primary access domain or zone name used by the identity-edge stack."
  type        = string
  default     = "bohdal.name"
}

# Allow shared metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used for Zero Trust and DNS resources."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for Zero Trust resources."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns public application hostnames."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for the existing cluster."
  type        = string
}

variable "allowed_user_email" {
  description = "Single-user allowlist for the shared Access group and policy."
  type        = string
  default     = "viktor.bohdal@gmail.com"
}

variable "kubernetes_namespace" {
  description = "Namespace that runs the cloudflared deployment."
  type        = string
  default     = "networking"
}

variable "cloudflared_secret_name" {
  description = "Secret name that stores the Cloudflare tunnel token."
  type        = string
  default     = "tunnel-token"
}

variable "cloudflared_deployment_name" {
  description = "Deployment name for the in-cluster cloudflared agent."
  type        = string
  default     = "cloudflared"
}

variable "cloudflared_image" {
  description = "Container image for the in-cluster cloudflared agent."
  type        = string
  default     = "cloudflare/cloudflared:latest"
}

variable "cloudflared_replicas" {
  description = "Replica count for the in-cluster cloudflared deployment."
  type        = number
  default     = 2
}

variable "tunnel_name" {
  description = "User-facing Cloudflare tunnel name."
  type        = string
  default     = "kubernetes-cluster-tunnel"
}

variable "tunnel_config_source" {
  description = "Cloudflare tunnel config source mode."
  type        = string
  default     = "cloudflare"
}

variable "tunnel_secret_b64" {
  description = "Existing Cloudflare tunnel secret as a base64-encoded string."
  type        = string
  sensitive   = true
}

variable "tunnel_ingress_hostnames" {
  description = "Public hostnames routed through the existing tunnel."
  type        = list(string)
  default     = ["*.bohdal.name"]
}

variable "tunnel_origin_service" {
  description = "Origin service URL for the main wildcard tunnel ingress."
  type        = string
  default     = "https://traefik.traefik.svc.cluster.local:443"
}
