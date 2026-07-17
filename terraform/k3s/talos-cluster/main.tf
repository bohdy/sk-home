locals {
  # OpenTofu map keys are sorted, so cp1 is the deterministic bootstrap node
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
  # OpenTofu owns the Talos PKI for this learning cluster. The values are
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
        logging = {
          # Forward structured service logs over a backpressure-capable stream.
          # The node tag supplies stable identity independently of sender IP.
          destinations = [
            {
              endpoint = var.talos_log_endpoint
              format   = "json_lines"
              extraTags = {
                node = each.value.hostname
              }
            },
          ]
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
    yamlencode({
      # Replace Talos' default automatic hostname with the committed inventory
      # name so Kubernetes node identity stays predictable across rebuilds.
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.value.hostname
    }),
    yamlencode({
      # Kernel logs are configured through Talos' dedicated multi-document
      # resource; JSON lines lets Vector share normalization with service logs.
      apiVersion = "v1alpha1"
      kind       = "KmsgLogConfig"
      name       = "observability"
      url        = var.talos_log_endpoint
    }),
  ]
}

data "talos_machine_configuration" "worker" {
  for_each = var.worker_nodes

  # Workers use the cluster PKI and endpoint but do not carry the API VIP or
  # control-plane-specific API server configuration.
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_endpoint_vip}:6443"
  machine_type       = "worker"
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
        logging = {
          # Workers use the same structured stream and stable node tag as the
          # control planes so one Vector pipeline covers the whole cluster.
          destinations = [
            {
              endpoint = var.talos_log_endpoint
              format   = "json_lines"
              extraTags = {
                node = each.value.hostname
              }
            },
          ]
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
            },
          ]
        }
      }
      cluster = {
        network = {
          # Every node must use the same external CNI ownership model.
          cni = {
            name = "none"
          }
        }
        proxy = {
          # Cilium replaces kube-proxy on workers as well as control planes.
          disabled = true
        }
      }
    }),
    yamlencode({
      # Workers use the same deterministic hostname policy as control planes.
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = each.value.hostname
    }),
    yamlencode({
      # Keep kernel delivery declarative for workers as well as control planes.
      apiVersion = "v1alpha1"
      kind       = "KmsgLogConfig"
      name       = "observability"
      url        = var.talos_log_endpoint
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

  # Static noCloud network data makes each node reachable before OpenTofu
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

resource "proxmox_virtual_environment_file" "talos_worker_user_data" {
  for_each = var.worker_nodes

  # Worker user-data contains a worker machine configuration signed by the same
  # cluster secrets, allowing the node to join without another bootstrap step.
  node_name    = each.value.host_node
  datastore_id = var.image.proxmox_snippet_datastore
  content_type = "snippets"

  source_raw {
    data      = data.talos_machine_configuration.worker[each.key].machine_configuration
    file_name = "${each.value.hostname}-talos-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "talos_worker_network_data" {
  for_each = var.worker_nodes

  # Static noCloud networking makes a new worker deterministic from first boot
  # and keeps cluster membership independent of DHCP state.
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
  # OpenTofu inventing new Proxmox names or IDs.
  name        = each.value.hostname
  node_name   = each.value.host_node
  vm_id       = each.value.vm_id
  description = "Talos control-plane node for ${var.cluster_name}, managed by OpenTofu"
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

  lifecycle {
    # Live Talos configuration is reconciled through the Talos API. Replacing a
    # versioned Proxmox snippet must not replace an established control plane.
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = var.worker_nodes

  # General-purpose workers are independently replaceable and do not carry
  # etcd or Kubernetes API server state.
  name        = each.value.hostname
  node_name   = each.value.host_node
  vm_id       = each.value.vm_id
  description = "Talos worker node for ${var.cluster_name}, managed by OpenTofu"
  tags        = distinct(concat(var.common_tags, ["worker"]))

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
    # The cloud-init disk transports only Talos noCloud configuration.
    datastore_id         = each.value.cloud_init_datastore_id
    user_data_file_id    = proxmox_virtual_environment_file.talos_worker_user_data[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.talos_worker_network_data[each.key].id
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

  lifecycle {
    # Keep worker VM lifecycle independent from noCloud snippet replacement;
    # the Talos apply resource below owns live configuration updates.
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = var.nodes

  # Prevent configuration reconciliation from rebooting multiple control-plane
  # nodes automatically. Changes that require reboot are staged for an explicit
  # rolling operation after the apply completes.
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
  ]

  node                        = split("/", each.value.ipv4_address)[0]
  endpoint                    = split("/", each.value.ipv4_address)[0]
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane[each.key].machine_configuration
  apply_mode                  = "staged_if_needing_reboot"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  # Workers use the same reboot-safe reconciliation mode so ordinary config
  # changes cannot unexpectedly remove the cluster's only worker.
  depends_on = [
    proxmox_virtual_environment_vm.worker,
  ]

  node                        = split("/", each.value.ipv4_address)[0]
  endpoint                    = split("/", each.value.ipv4_address)[0]
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  apply_mode                  = "staged_if_needing_reboot"
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

  lifecycle {
    # Bootstrap is a one-shot Talos operation. If OpenTofu replaces the
    # control-plane VMs, replace this resource too so the rebuilt nodes form a
    # fresh etcd cluster instead of inheriting stale bootstrap state.
    replace_triggered_by = [
      proxmox_virtual_environment_vm.control_plane,
    ]
  }

  timeouts = {
    create = "10m"
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  # Fetch kubeconfig only after Talos bootstrap completes so OpenTofu does not
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
