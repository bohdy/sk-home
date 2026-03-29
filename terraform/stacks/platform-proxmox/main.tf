locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      site        = var.site_name
      stack       = "platform-proxmox"
      managed_by  = "terraform"
    },
    var.additional_tags
  )

  # The live platform inventory is intentionally committed here so Terraform
  # can import the current Proxmox objects without discovering them dynamically.
  cluster_nodes = {
    k8s_master = {
      vm_id            = 103
      name             = "k8s-master"
      ip               = "10.1.20.101"
      memory_dedicated = 6144
      memory_floating  = 6144
      mac_address      = "BC:24:11:06:D5:7E"
      startup_order    = 1
      is_master        = true
      file_name        = "setup-k8s-master.yaml"
      tags             = ["homelab", "k8s", "kubernetes", "master", "pulumi"]
      cdrom_file_id    = "cdrom"
    }
    k8s_worker_1 = {
      vm_id            = 102
      name             = "k8s-worker-1"
      ip               = "10.1.20.102"
      memory_dedicated = 6144
      memory_floating  = 6144
      mac_address      = "BC:24:11:CA:1B:17"
      startup_order    = 10
      is_master        = false
      file_name        = "setup-k8s-worker-1.yaml"
      tags             = ["homelab", "k8s", "kubernetes", "pulumi", "worker"]
      cdrom_file_id    = "cdrom"
    }
    k8s_worker_2 = {
      vm_id            = 100
      name             = "k8s-worker-2"
      ip               = "10.1.20.103"
      memory_dedicated = 6144
      memory_floating  = 6144
      mac_address      = "BC:24:11:39:38:58"
      startup_order    = 10
      is_master        = false
      file_name        = "setup-k8s-worker-2.yaml"
      tags             = ["homelab", "k8s", "kubernetes", "pulumi", "worker"]
      cdrom_file_id    = "cdrom"
    }
  }

  openclaw_vm = {
    vm_id            = 104
    name             = "vm-openclaw"
    ip               = "10.1.20.110"
    memory_dedicated = 4096
    memory_floating  = 4096
    mac_address      = "BC:24:11:33:B9:B1"
    startup_order    = 50
    file_name        = "vm-openclaw-setup.yaml"
    tags             = ["homelab", "pulumi", "ubuntu"]
    cdrom_file_id    = "none"
  }

  # Keep the current bootstrap template path explicit so the stack remains
  # reviewable even though the rendered content includes secrets at runtime.
  cluster_cloud_init = {
    for key, node in local.cluster_nodes :
    key => templatefile("${path.module}/templates/cluster-user-data.yaml.tftpl", {
      bohdy_username                        = var.bohdy_username
      bohdy_ssh_public_key                  = var.bohdy_ssh_public_key
      docker_auth_base64                    = var.docker_auth_base64
      docker_password                       = var.docker_password
      docker_username                       = var.docker_username
      github_actions_proxmox_ssh_public_key = var.github_actions_proxmox_ssh_public_key
      hostname                              = node.name
      is_master                             = tostring(node.is_master)
      k8s_token                             = var.k8s_token
      master_ip                             = local.cluster_nodes.k8s_master.ip
      node_subnet                           = "10.1.20.0/24"
    })
  }

  openclaw_cloud_init = templatefile("${path.module}/templates/openclaw-user-data.yaml.tftpl", {
    bohdy_username       = var.bohdy_username
    bohdy_ssh_public_key = var.bohdy_ssh_public_key
    hostname             = local.openclaw_vm.name
  })
}

# Preserve the cluster-node cloud-init snippets as imported Proxmox files. The
# raw content is rendered from committed templates, but drift in the secret-filled
# payload is ignored until the missing Bitwarden bootstrap values are supplied.
resource "proxmox_virtual_environment_file" "cluster_cloud_init" {
  for_each = local.cluster_nodes

  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "snippets"

  dynamic "source_raw" {
    for_each = var.manage_imported_snippet_payloads ? [1] : []

    content {
      data      = local.cluster_cloud_init[each.key]
      file_name = each.value.file_name
    }
  }

  lifecycle {
    ignore_changes = [
      overwrite,
      source_raw,
      timeout_upload,
    ]
  }
}

# Preserve the standalone Ubuntu bootstrap snippet that seeds vm-openclaw.
resource "proxmox_virtual_environment_file" "openclaw_cloud_init" {
  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "snippets"

  dynamic "source_raw" {
    for_each = var.manage_imported_snippet_payloads ? [1] : []

    content {
      data      = local.openclaw_cloud_init
      file_name = local.openclaw_vm.file_name
    }
  }

  lifecycle {
    ignore_changes = [
      overwrite,
      source_raw,
      timeout_upload,
    ]
  }
}

# Import the three current Kubernetes VMs without changing their IDs, MACs, or
# cloud-init wiring.
resource "proxmox_virtual_environment_vm" "cluster_nodes" {
  for_each = local.cluster_nodes

  vm_id     = each.value.vm_id
  node_name = var.proxmox_node_name
  name      = each.value.name
  started   = true
  on_boot   = true
  tags      = each.value.tags

  scsi_hardware = "virtio-scsi-pci"

  dynamic "clone" {
    for_each = var.declare_clone_source ? [1] : []

    content {
      vm_id = var.template_vm_id
      full  = true
    }
  }

  cdrom {
    interface = "ide3"
    file_id   = each.value.cdrom_file_id
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "qemu64"
    numa    = false
  }

  memory {
    dedicated = each.value.memory_dedicated
    floating  = each.value.memory_floating
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 32
    aio          = "io_uring"
    backup       = true
    cache        = "none"
    discard      = "on"
    iothread     = false
    replicate    = true
    ssd          = false
  }

  network_device {
    bridge      = "vmbr0"
    firewall    = false
    model       = "virtio"
    mac_address = each.value.mac_address
    vlan_id     = 20
  }

  agent {
    enabled = true
    trim    = false
    type    = "virtio"
  }

  initialization {
    dns {
      servers = ["8.8.8.8", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.1.20.1"
      }
    }

    user_account {
      username = var.bohdy_username
      keys     = [var.bohdy_ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.cluster_cloud_init[each.key].id
  }

  serial_device {
    device = "socket"
  }

  startup {
    order      = each.value.startup_order
    up_delay   = 10
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
}

# Import the standalone Ubuntu VM with the same preserved network identity and
# cloud-init snippet as the Pulumi-managed source.
resource "proxmox_virtual_environment_vm" "openclaw" {
  vm_id     = local.openclaw_vm.vm_id
  node_name = var.proxmox_node_name
  name      = local.openclaw_vm.name
  started   = true
  on_boot   = true
  tags      = local.openclaw_vm.tags

  scsi_hardware = "virtio-scsi-pci"

  dynamic "clone" {
    for_each = var.declare_clone_source ? [1] : []

    content {
      vm_id = var.template_vm_id
      full  = true
    }
  }

  cdrom {
    interface = "ide3"
    file_id   = local.openclaw_vm.cdrom_file_id
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "qemu64"
    numa    = false
  }

  memory {
    dedicated = local.openclaw_vm.memory_dedicated
    floating  = local.openclaw_vm.memory_floating
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 32
    aio          = "io_uring"
    backup       = true
    cache        = "none"
    discard      = "on"
    iothread     = false
    replicate    = true
    ssd          = false
  }

  network_device {
    bridge      = "vmbr0"
    firewall    = false
    model       = "virtio"
    mac_address = local.openclaw_vm.mac_address
    vlan_id     = 20
  }

  agent {
    enabled = true
    trim    = false
    type    = "virtio"
  }

  initialization {
    dns {
      servers = ["8.8.8.8", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "${local.openclaw_vm.ip}/24"
        gateway = "10.1.20.1"
      }
    }

    user_account {
      username = var.bohdy_username
      keys     = [var.bohdy_ssh_public_key]
    }

    user_data_file_id = proxmox_virtual_environment_file.openclaw_cloud_init.id
  }

  serial_device {
    device = "socket"
  }

  startup {
    order      = local.openclaw_vm.startup_order
    up_delay   = 10
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
}

# Preserve the live Proxmox metrics fan-out to VictoriaMetrics so the existing
# observability path keeps working during the ownership handoff.
resource "proxmox_virtual_environment_metrics_server" "victoria_metrics" {
  name            = "victoriametrics"
  type            = "influxdb"
  server          = "10.1.30.210"
  port            = 8089
  influx_db_proto = "udp"
}
