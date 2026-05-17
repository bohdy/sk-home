resource "proxmox_virtual_environment_vm" "test_server" {
  name        = "k3s-master"
  node_name   = "pve"
  description = "K3s master node for testing Terraform-managed Proxmox clusters"
  boot_order  = ["scsi0"]

  tags = ["terraform", "k3s", "master"]

  agent {
    enabled = false
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 2048
    floating  = 4096
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 20
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = data.proxmox_file.cloud_init_iso.id
    interface    = "scsi0"
    size         = 13
  }

  initialization {
    # uncomment and specify the datastore for cloud-init disk if default `local-lvm` is not available

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.ignition_snippet.id
  }
}

resource "proxmox_virtual_environment_file" "ignition_snippet" {
  node_name    = "pve"
  datastore_id = "local"
  content_type = "snippets"

  source_raw {
    data      = data.ct_config.machine-ignition.rendered
    file_name = "k3s-master.ign"
  }
}

data "proxmox_file" "cloud_init_iso" {
  node_name    = "pve"
  datastore_id = "local"
  content_type = "import"
  file_name    = "flatcar_production_proxmoxve_image.qcow2"
}


data "ct_config" "machine-ignition" {
  content = file("${path.module}/butane-configs/k3s-master.yaml")
  strict  = true
}

output "k3s_master_node_id" {
  value = proxmox_virtual_environment_vm.test_server.id
}
