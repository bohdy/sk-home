# Keep the k3s Blocky DNS stack inputs explicit so desired state stays
# reviewable and DNS behavior is not hidden in resource literals.
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
  description = "Path to a kubeconfig file for the new k3s cluster."
  type        = string
}

variable "namespace_name" {
  description = "Namespace that owns the Blocky workload in the new cluster."
  type        = string
  default     = "app-blocky-k3s"
}

variable "dns_service_name" {
  description = "LoadBalancer Service name that serves DNS on port 53."
  type        = string
  default     = "blocky-dns"
}

variable "metrics_service_name" {
  description = "ClusterIP Service name used for Blocky HTTP/metrics access."
  type        = string
  default     = "blocky-metrics"
}

variable "dns_ip" {
  description = "MetalLB IP assigned to the external Blocky DNS service."
  type        = string
}

variable "storage_class_name" {
  description = "Storage class used for query-log persistence when enabled."
  type        = string
  default     = "synology-nfs"
}

variable "log_pvc_name" {
  description = "PVC name used to persist Blocky query logs."
  type        = string
  default     = "blocky-logs"
}

variable "log_pvc_size" {
  description = "Requested PVC size for Blocky query logs."
  type        = string
  default     = "512Mi"
}

variable "blocky_image" {
  description = "Blocky container image pin used by the DaemonSet."
  type        = string
  default     = "spx01/blocky:v0.29.0"
}

variable "blocky_timezone" {
  description = "Timezone used for Blocky logs and internal scheduling."
  type        = string
  default     = "Europe/Prague"
}

variable "upstreams" {
  description = "Default recursive upstream DNS resolvers used by Blocky."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "denylist_urls" {
  description = "External denylist URLs used for DNS blocking."
  type        = list(string)
  default     = ["https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"]
}

variable "custom_dns_records" {
  description = "Local DNS mappings where key is FQDN and value is IPv4/IPv6 address."
  type        = map(string)
  default     = {}
}

variable "metrics_enabled" {
  description = "Whether Blocky should expose Prometheus metrics."
  type        = bool
  default     = true
}

variable "metrics_path" {
  description = "HTTP path for Blocky Prometheus metrics export."
  type        = string
  default     = "/metrics"
}

variable "query_log_mode" {
  description = "Blocky query log sink type, for example csv-client or console."
  type        = string
  default     = "csv-client"
}

variable "query_log_target" {
  description = "Blocky query log output target directory used by csv-client logging."
  type        = string
  default     = "/logs"
}

variable "query_log_retention_days" {
  description = "Retention period in days for CSV query logs."
  type        = number
  default     = 14
}

variable "query_log_flush_interval" {
  description = "Flush interval for query logs, expressed in Go duration format."
  type        = string
  default     = "5s"
}

variable "log_privacy" {
  description = "Whether Blocky should mask privacy-sensitive fields in logs."
  type        = bool
  default     = true
}
