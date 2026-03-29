variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
}

variable "environment" {
  description = "Deployment environment name, such as home or lab."
  type        = string
  default     = "home"
}

variable "observability_site_name" {
  description = "Logical observability site name used by this stack."
  type        = string
  default     = "primary"
}

variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file for the existing cluster."
  type        = string
}

variable "namespace" {
  description = "Namespace that contains the live monitoring workloads."
  type        = string
  default     = "monitoring"
}

variable "storage_class_name" {
  description = "Storage class used by the imported monitoring PVCs."
  type        = string
  default     = "synology-nfs"
}

variable "victoria_metrics_external_ip" {
  description = "Existing MetalLB IP preserved for the VictoriaMetrics external service."
  type        = string
  default     = "10.1.30.210"
}

variable "grafana_hostname" {
  description = "Public Grafana hostname preserved by the imported ingress."
  type        = string
  default     = "grafana.bohdal.name"
}

variable "kube_state_metrics_chart_version" {
  description = "Pinned chart version for the imported kube-state-metrics Helm release."
  type        = string
  default     = "7.2.0"
}

variable "unpoller_unifi_url" {
  description = "Internal UniFi URL consumed by the imported Unpoller deployment."
  type        = string
  default     = "https://unifi-gui.unifi.svc.cluster.local:8443"
}

variable "unpoller_username" {
  description = "UniFi username injected into the imported Unpoller secret."
  type        = string
  sensitive   = true
}

variable "unpoller_password" {
  description = "UniFi password injected into the imported Unpoller secret."
  type        = string
  sensitive   = true
}
