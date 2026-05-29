locals {
  # Terraform map keys are sorted, so cp1 is the deterministic bootstrap node
  # for the default inventory and any future inventory with the same key style.
  bootstrap_node_key = keys(var.nodes)[0]
  bootstrap_node_ip  = split("/", var.nodes[local.bootstrap_node_key].ipv4_address)[0]

  control_plane_ips = [
    for node in var.nodes : split("/", node.ipv4_address)[0]
  ]

  # Include the VIP and node IPs in the Kubernetes API certificate so operators
  # can use either the HA endpoint or a direct node endpoint during recovery.
  api_server_cert_sans = distinct(concat(
    [var.cluster_endpoint_vip],
    local.control_plane_ips,
    var.cluster_endpoint_sans,
  ))
}

resource "talos_machine_secrets" "cluster" {
  # Terraform owns the Talos PKI for this learning cluster. The values are
  # sensitive and live in the configured remote state backend.
}

data "talos_machine_configuration" "control_plane" {
  for_each = var.nodes

  # Render one control-plane configuration per VM so static networking and the
  # install target are explicit while Proxmox continues to supply hostname.
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_endpoint_vip}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = each.value.install_disk
          image = "${var.image.factory_url}/installer/${each.value.update ? local.update_schematic_id : local.schematic_id}:${each.value.update ? local.update_version : local.image_version}"
        }
        network = {
          nameservers = var.cluster_dns_servers
          interfaces = [
            {
              interface = each.value.network_interface
              addresses = [
                each.value.ipv4_address,
              ]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.cluster_gateway
                },
              ]
              vip = {
                ip = var.cluster_endpoint_vip
              }
            },
          ]
        }
      }
      cluster = {
        network = {
          # Cilium is bootstrapped after Talos forms the control plane, so Talos
          # must not install its default CNI manifest during cluster creation.
          cni = {
            name = "none"
          }
        }
        proxy = {
          # Cilium runs kube-proxy replacement for this cluster, so Talos should
          # not deploy kube-proxy into the bootstrap manifests.
          disabled = true
        }
        apiServer = {
          certSANs = local.api_server_cert_sans
        }
      }
    }),
  ]
}

data "talos_client_configuration" "cluster" {
  # Generate talosconfig from the same secrets used by the machine configs so
  # recovery operations can target either the VIP or individual control planes.
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [var.cluster_endpoint_vip]
  nodes                = local.control_plane_ips
}

resource "proxmox_virtual_environment_file" "talos_user_data" {
  for_each = var.nodes

  # Talos noCloud consumes machine configuration as user-data on first boot.
  node_name    = each.value.host_node
  datastore_id = var.image.proxmox_snippet_datastore
  content_type = "snippets"

  source_raw {
    data      = data.talos_machine_configuration.control_plane[each.key].machine_configuration
    file_name = "${each.value.hostname}-talos-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "talos_network_data" {
  for_each = var.nodes

  # Static noCloud network data makes each node reachable before Terraform
  # calls the Talos API for bootstrap and kubeconfig retrieval.
  node_name    = each.value.host_node
  datastore_id = var.image.proxmox_snippet_datastore
  content_type = "snippets"

  source_raw {
    data = yamlencode({
      version = 1
      config = [
        {
          type        = "physical"
          name        = each.value.network_interface
          mac_address = each.value.mac_address
          subnets = [
            {
              type    = "static"
              address = split("/", each.value.ipv4_address)[0]
              netmask = cidrnetmask(each.value.ipv4_address)
              gateway = var.cluster_gateway
            },
          ]
        },
      ]
    })
    file_name = "${each.value.hostname}-talos-network-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = var.nodes

  # Keep VM identity deterministic so the cluster can be rebuilt without
  # Terraform inventing new Proxmox names or IDs.
  name        = each.value.hostname
  node_name   = each.value.host_node
  vm_id       = each.value.vm_id
  description = "Talos control-plane node for ${var.cluster_name}, managed by Terraform"
  tags        = distinct(concat(var.common_tags, ["control-plane"]))

  started         = true
  on_boot         = true
  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = each.value.memory_mb
  }

  disk {
    datastore_id = each.value.disk_datastore_id
    file_id      = proxmox_download_file.talos_nocloud_image[local.node_image_keys[each.key]].id
    interface    = each.value.disk_interface
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size_gb
  }

  initialization {
    # The cloud-init disk only transports noCloud data; Talos itself ignores
    # ordinary Linux user-account settings.
    datastore_id         = each.value.cloud_init_datastore_id
    user_data_file_id    = proxmox_virtual_environment_file.talos_user_data[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.talos_network_data[each.key].id
  }

  network_device {
    bridge      = each.value.bridge
    vlan_id     = each.value.vlan_id
    mac_address = each.value.mac_address
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

resource "talos_machine_bootstrap" "cluster" {
  # Bootstrap only after all control-plane VMs have their first-boot noCloud
  # data attached, so the first node can form etcd with the final cluster config.
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
  ]

  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip
  client_configuration = talos_machine_secrets.cluster.client_configuration

  timeouts = {
    create = "10m"
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  # Fetch kubeconfig only after Talos bootstrap completes so Terraform does not
  # expose a partial Kubernetes client configuration.
  depends_on = [
    talos_machine_bootstrap.cluster,
  ]

  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip
  client_configuration = talos_machine_secrets.cluster.client_configuration

  timeouts = {
    create = "5m"
    update = "5m"
  }
}
