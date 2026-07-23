# Keep the gateway endpoint configurable so the stack does not encode a host
# name in provider configuration.
variable "mikrotik_gw_hosturl" {
  description = "RouterOS provider URL for the MikroTik gateway device."
  type        = string
  default     = "https://gw.bohdal.name/"
}

variable "mikrotik_username" {
  description = "Dedicated RouterOS automation username sourced from Bitwarden."
  type        = string
}

variable "mikrotik_password" {
  description = "Dedicated RouterOS automation password sourced from Bitwarden."
  type        = string
  sensitive   = true
}

variable "mikrotik_insecure" {
  description = "Whether to accept the gateway's current self-signed TLS certificate."
  type        = bool
  default     = true
}

# One scope declaration keeps each DHCP server, pool, and network option tied
# together without inferring RouterOS names from unrelated infrastructure code.
variable "dhcp_scopes" {
  description = "Gateway DHCP scopes, including pool, server, and network settings."
  type = map(object({
    interface   = string
    pool_name   = string
    range_start = string
    range_end   = string
    subnet      = string
    gateway     = string
    dns_servers = list(string)
    domain      = optional(string)
    lease_time  = string
    add_arp     = optional(bool, false)
    option_set  = optional(string)
    comment     = optional(string)
  }))
}

variable "dhcp_reservations" {
  description = "Existing static RouterOS DHCP reservations to retain under the migrated stack."
  type = map(object({
    server      = string
    address     = string
    mac_address = string
    client_id   = optional(string)
    comment     = optional(string)
  }))
}
