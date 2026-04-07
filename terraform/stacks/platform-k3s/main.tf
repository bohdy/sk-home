locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      stack       = "platform-k3s"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # Split the nodes map into server and agent subsets so downstream resources
  # can derive the server IP for agent join configuration.
  server_nodes = { for k, v in var.nodes : k => v if v.role == "server" }
  agent_nodes  = { for k, v in var.nodes : k => v if v.role == "agent" }

  # Resolve the single server node IP for agent join URLs. The stack expects
  # exactly one server node in the current single-server topology.
  server_ip = values(local.server_nodes)[0].ip

}

# --- Butane to Ignition transpilation ---

# Transpile each server node's Butane YAML template into Ignition JSON.
data "ct_config" "server" {
  for_each = local.server_nodes

  content = templatefile("${path.module}/templates/k3s-server.yaml.tftpl", {
    hostname       = each.key
    ssh_public_key = var.ssh_public_key
    k3s_version    = var.k3s_version
    k3s_token      = var.k3s_token
    node_ip        = each.value.ip
    prefix_length  = var.network_prefix_length
    gateway        = var.network_gateway
    dns_servers    = join(" ", var.dns_servers)
  })
  strict = true
}

# Transpile each agent node's Butane YAML template into Ignition JSON.
data "ct_config" "agent" {
  for_each = local.agent_nodes

  content = templatefile("${path.module}/templates/k3s-agent.yaml.tftpl", {
    hostname       = each.key
    ssh_public_key = var.ssh_public_key
    k3s_version    = var.k3s_version
    k3s_token      = var.k3s_token
    node_ip        = each.value.ip
    server_ip      = local.server_ip
    prefix_length  = var.network_prefix_length
    gateway        = var.network_gateway
    dns_servers    = join(" ", var.dns_servers)
  })
  strict = true
}

# --- Ignition snippet uploads ---

# Upload per-node Ignition JSON as Proxmox snippets so Proxmox cloud-init
# custom user-data can reference them at first boot.
resource "proxmox_virtual_environment_file" "ignition" {
  for_each = var.nodes

  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "snippets"

  source_raw {
    data = (
      each.value.role == "server"
      ? data.ct_config.server[each.key].rendered
      : data.ct_config.agent[each.key].rendered
    )
    file_name = "${each.key}.ign"
  }

  lifecycle {
    ignore_changes = [
      overwrite,
      timeout_upload,
    ]
  }
}

# --- Proxmox VMs ---

# Create one VM per node entry, cloned from the Flatcar template. The
# for_each key becomes the VM name and hostname.
resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  vm_id     = each.value.vm_id
  node_name = var.proxmox_node_name
  name      = each.key
  started   = true
  on_boot   = true
  tags      = ["flatcar", "k3s", each.value.role, "terraform"]

  scsi_hardware = "virtio-scsi-pci"

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  # Resize the cloned disk to the desired size. Flatcar auto-expands the
  # root partition on first boot to fill the available space.
  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = each.value.disk_size
    discard      = "on"
    aio          = "io_uring"
    backup       = true
    cache        = "none"
    iothread     = false
    replicate    = true
    ssd          = false
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  agent {
    enabled = true
    trim    = false
    type    = "virtio"
  }

  # Reference the per-node Ignition snippet as Proxmox custom cloud-init
  # user-data and keep cloud-init network metadata as a static-IP fallback.
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.ignition[each.key].id

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.network_prefix_length}"
        gateway = var.network_gateway
      }
    }
  }

  serial_device {
    device = "socket"
  }

  startup {
    # Server nodes start first so the API is ready before agents join.
    order      = each.value.role == "server" ? 1 : 10
    up_delay   = 15
    down_delay = 10
  }

  vga {
    type = "serial0"
  }

  lifecycle {
    ignore_changes = [
      boot_order,
      disk[0].speed,
      initialization[0].user_data_file_id,
      keyboard_layout,
    ]
  }

  depends_on = [proxmox_virtual_environment_file.ignition]
}
