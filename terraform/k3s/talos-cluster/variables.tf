variable "cluster_name" {
  # Keep the Talos and Kubernetes identity stable so regenerated client
  # configuration points at the same cluster after routine Terraform changes.
  description = "Name used for the Talos and Kubernetes cluster."
  type        = string
  default     = "sk-talos"
}

variable "cluster_endpoint_vip" {
  # The Kubernetes API endpoint is a Talos-managed VIP shared by the control
  # plane nodes, avoiding a dependency on a separate load balancer for v1.
  description = "Talos virtual IP used as the Kubernetes API endpoint."
  type        = string
  default     = "10.1.20.40"
}

variable "cluster_gateway" {
  # Static node networking needs an explicit gateway because first boot must be
  # deterministic before any Kubernetes services exist.
  description = "IPv4 gateway used by Talos control-plane nodes."
  type        = string
  default     = "10.1.20.1"
}

variable "cluster_dns_servers" {
  # Prefer the local gateway DNS path by default so early boot does not depend
  # on public resolvers unless operators opt in later.
  description = "DNS servers configured in Talos machine networking."
  type        = list(string)
  default     = ["10.1.20.1"]
}

variable "cluster_endpoint_sans" {
  # Additional API server SANs are optional; the VIP and node addresses are
  # always added by local configuration.
  description = "Additional Kubernetes API server certificate SANs."
  type        = list(string)
  default     = []
}

variable "talos_version" {
  # Talos is pinned intentionally so image factory downloads, installer images,
  # and generated machine configuration move together during upgrades.
  description = "Talos Linux version for the VM image and generated configs."
  type        = string
  default     = "v1.13.1"
}

variable "kubernetes_version" {
  # Match the Kubernetes version supported by the pinned Talos release instead
  # of relying on provider defaults that may drift over time.
  description = "Kubernetes version rendered into the Talos machine configs."
  type        = string
  default     = "1.36.0"
}

variable "common_tags" {
  # Tags make the Terraform-owned cluster easy to identify in Proxmox without
  # encoding ownership only in the VM name.
  description = "Common Proxmox tags applied to every Talos VM."
  type        = list(string)
  default     = ["terraform", "talos", "kubernetes"]
}

variable "image" {
  # The schematic can be overridden for experiments, but the committed default
  # comes from image/schematic.yaml so extension changes are reviewable.
  description = "Talos image factory settings."
  type = object({
    factory_url               = optional(string, "https://factory.talos.dev")
    schematic                 = optional(string)
    version                   = optional(string)
    update_schematic          = optional(string)
    update_version            = optional(string)
    arch                      = optional(string, "amd64")
    platform                  = optional(string, "nocloud")
    proxmox_image_datastore   = optional(string, "local")
    proxmox_snippet_datastore = optional(string, "local")
  })
  default = {}
}

variable "nodes" {
  # The initial implementation is intentionally control-plane only. Per-node
  # entries still carry placement and sizing so future worker additions do not
  # require reshaping the whole stack.
  description = "Talos control-plane node inventory."
  type = map(object({
    hostname                = string
    ipv4_address            = string
    mac_address             = string
    host_node               = optional(string, "pve")
    vm_id                   = optional(number)
    cpu_cores               = optional(number, 2)
    memory_mb               = optional(number, 4096)
    disk_size_gb            = optional(number, 32)
    disk_datastore_id       = optional(string, "local-lvm")
    cloud_init_datastore_id = optional(string, "local-lvm")
    bridge                  = optional(string, "vmbr0")
    vlan_id                 = optional(number, 20)
    network_interface       = optional(string, "eth0")
    disk_interface          = optional(string, "virtio0")
    install_disk            = optional(string, "/dev/vda")
    update                  = optional(bool, false)
  }))

  default = {
    cp1 = {
      hostname     = "sk-talos-cp-1"
      ipv4_address = "10.1.20.41/24"
      mac_address  = "BC:24:11:20:40:41"
      vm_id        = 1041
    }
    cp2 = {
      hostname     = "sk-talos-cp-2"
      ipv4_address = "10.1.20.42/24"
      mac_address  = "BC:24:11:20:40:42"
      vm_id        = 1042
    }
    cp3 = {
      hostname     = "sk-talos-cp-3"
      ipv4_address = "10.1.20.43/24"
      mac_address  = "BC:24:11:20:40:43"
      vm_id        = 1043
    }
  }

  validation {
    condition     = length(var.nodes) == 3
    error_message = "The first Talos implementation expects exactly three control-plane nodes."
  }
}

variable "proxmox_endpoint" {
  # Keep the Proxmox API URL outside source control so the same stack can be
  # pointed at the intended environment through Bitwarden-backed variables.
  description = "Proxmox API endpoint."
  type        = string
}

variable "proxmox_api_token" {
  # API tokens are sensitive because Terraform plans can otherwise expose the
  # credential material used to change the Proxmox cluster.
  description = "Proxmox API token."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key" {
  # The provider accepts private keys as plain strings; providers.tf normalizes
  # escaped newlines so Bitwarden and shell exports can carry the value safely.
  description = "SSH private key used by the Proxmox provider for file uploads."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_username" {
  # SSH may use a different principal than API-token operations, so keep it as
  # an explicit input instead of inferring it from the token identity.
  description = "SSH username used by the Proxmox provider."
  type        = string
}

variable "proxmox_insecure" {
  # The current lab endpoint uses local TLS trust, so this stays configurable
  # while defaulting to the existing stack behavior.
  description = "Whether the Proxmox provider skips TLS certificate verification."
  type        = bool
  default     = true
}
