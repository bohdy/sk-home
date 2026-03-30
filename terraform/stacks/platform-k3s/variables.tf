# Keep the k3s platform inputs explicit so the stack stays reviewable and new
# nodes can be added by extending the nodes map without touching resource blocks.

variable "project_name" {
  description = "Human-readable project name for this infrastructure stack."
  type        = string
  default     = "sk-home"
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

# --- Proxmox connection ---

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL."
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token string."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key" {
  description = "Unencrypted Proxmox root SSH key used for snippet uploads."
  type        = string
  sensitive   = true
}

variable "proxmox_node_name" {
  description = "Single Proxmox node that hosts the k3s cluster VMs."
  type        = string
  default     = "pve"
}

# --- Flatcar template ---

variable "template_vm_id" {
  description = "Proxmox VM ID of the Flatcar template created by create-flatcar-template.sh."
  type        = number
}

# --- Node inventory ---

variable "nodes" {
  description = <<-EOT
    Map of k3s cluster nodes. Each key becomes the VM name and hostname.
    Add a new entry and apply to scale the cluster.
    The role field must be "server" or "agent".
  EOT
  type = map(object({
    vm_id     = number
    ip        = string
    role      = string
    memory    = optional(number, 6144)
    cores     = optional(number, 2)
    disk_size = optional(number, 32)
  }))

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["server", "agent"], n.role)])
    error_message = "Each node role must be either 'server' or 'agent'."
  }
}

# --- Network ---

variable "vlan_id" {
  description = "VLAN ID for the k3s node network interfaces."
  type        = number
  default     = 20
}

variable "network_bridge" {
  description = "Proxmox network bridge for the k3s node NICs."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default gateway IP for the k3s nodes."
  type        = string
}

variable "network_prefix_length" {
  description = "Subnet prefix length for the k3s node IPs."
  type        = number
  default     = 24
}

variable "dns_servers" {
  description = "DNS server addresses for the k3s nodes."
  type        = list(string)
}

# --- k3s ---

variable "k3s_version" {
  description = "k3s release version for the sysext image (e.g. v1.32.3+k3s1)."
  type        = string
}

variable "k3s_token" {
  description = "Shared secret token used by agents to join the k3s cluster."
  type        = string
  sensitive   = true
}

# --- SSH ---

variable "ssh_public_key" {
  description = "SSH public key for the core user on Flatcar nodes."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB0Ql0coSrrDTpGmN7BDs9GtxHk0RX4HX8bQNmF+hQb viktor@bohdal.name"
}
