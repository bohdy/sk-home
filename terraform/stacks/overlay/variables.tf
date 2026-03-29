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

# Describe the tailnet or overlay domain managed by this stack.
variable "tailnet_name" {
  description = "Tailnet name used by the overlay stack."
  type        = string
  default     = "example.tailnet"
}

# Allow shared metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for the existing cluster."
  type        = string
}

variable "kubernetes_namespace" {
  description = "Namespace that runs the Tailscale subnet router."
  type        = string
  default     = "infra-tailscale"
}

variable "tailscale_name" {
  description = "Base name for the Tailscale Kubernetes objects."
  type        = string
  default     = "tailscale"
}

variable "tailscale_authkey" {
  description = "Tailscale auth key used by the existing subnet router."
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Advertised hostname for the Tailscale subnet router."
  type        = string
  default     = "sk-k8s-subnet-router"
}

variable "tailscale_routes" {
  description = "Routes advertised by the existing subnet router."
  type        = string
  default     = "10.1.0.0/16"
}

variable "tailscale_image" {
  description = "Container image for the Tailscale subnet router."
  type        = string
  default     = "tailscale/tailscale:latest"
}

variable "tailscale_replicas" {
  description = "Replica count for the live Tailscale deployment."
  type        = number
  default     = 2
}
