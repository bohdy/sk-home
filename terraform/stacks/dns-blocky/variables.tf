# Keep the imported Blocky stack inputs centralized here so the live DNS
# workload configuration remains reviewable and shared desired state stays out
# of ad hoc resource literals.
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

variable "namespace_name" {
  description = "Namespace that owns the Blocky workload."
  type        = string
  default     = "app-blocky"
}

variable "service_name" {
  description = "LoadBalancer service name for Blocky."
  type        = string
  default     = "blocky-service"
}

variable "dns_ip" {
  description = "Existing MetalLB IP used for the Blocky service."
  type        = string
  default     = "10.1.30.255"
}

variable "storage_class_name" {
  description = "Storage class used by the existing Blocky PVC."
  type        = string
  default     = "synology-nfs"
}

variable "pvc_name" {
  description = "Blocky PVC name."
  type        = string
  default     = "blocky-pvc-334f248e"
}

variable "config_map_name" {
  description = "Blocky ConfigMap name."
  type        = string
  default     = "blocky-config-d14f1f13"
}

variable "daemonset_name" {
  description = "Blocky DaemonSet name."
  type        = string
  default     = "blocky-9d18cedb"
}
