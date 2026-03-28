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

# Capture site-level identity for physical network resources.
variable "site_name" {
  description = "Logical site name used by the network-core stack."
  type        = string
  default     = "primary"
}

# Allow shared metadata without hardcoding tags into resources.
variable "additional_tags" {
  description = "Additional metadata tags to merge into the shared tag map."
  type        = map(string)
  default     = {}
}

# Keep the gateway management endpoint configurable instead of embedding it in
# provider configuration.
variable "mikrotik_gw_hosturl" {
  description = "RouterOS provider URL for the MikroTik gateway device."
  type        = string
}

# Keep the first switch management endpoint configurable instead of embedding it
# in provider configuration.
variable "mikrotik_switch_1pp_hosturl" {
  description = "RouterOS provider URL for the MikroTik Switch 1PP device."
  type        = string
}

# Keep the second switch management endpoint configurable instead of embedding
# it in provider configuration.
variable "mikrotik_switch_1np_hosturl" {
  description = "RouterOS provider URL for the MikroTik Switch 1NP device."
  type        = string
}

# Keep the transitional RouterOS automation account input available in the
# parent root until DHCP resources have been migrated into the nested state.
variable "mikrotik_username" {
  description = "Username for the RouterOS automation account retained for transitional state operations."
  type        = string
}

# Keep the transitional RouterOS password input available in the parent root
# until DHCP resources have been migrated into the nested state.
variable "mikrotik_password" {
  description = "Password for the RouterOS automation account retained for transitional state operations."
  type        = string
  sensitive   = true
}

# Keep the transitional RouterOS TLS toggle available in the parent root until
# DHCP resources have been migrated into the nested state.
variable "mikrotik_insecure" {
  description = "Whether the parent root should skip TLS verification during transitional RouterOS state operations."
  type        = bool
  default     = true
}
