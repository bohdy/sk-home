locals {
  # Keep the committed schematic in YAML so extension changes are reviewed as
  # normal source while still allowing temporary overrides through variables.
  image_schematic = coalesce(var.image.schematic, file("${path.module}/image/schematic.yaml"))
  image_version   = coalesce(var.image.version, var.talos_version)

  update_schematic = coalesce(var.image.update_schematic, local.image_schematic)
  update_version   = coalesce(var.image.update_version, local.image_version)

  schematic_id        = jsondecode(data.http.schematic_id.response_body)["id"]
  update_schematic_id = jsondecode(data.http.updated_schematic_id.response_body)["id"]

  image_id        = "${local.schematic_id}_${local.image_version}"
  update_image_id = "${local.update_schematic_id}_${local.update_version}"

  # Treat both roles as image consumers while keeping their VM and Talos
  # configuration resources separate for lifecycle safety.
  all_nodes = merge(var.nodes, var.worker_nodes)

  # Collapse duplicate downloads per Proxmox host/image pair so all VMs on the
  # same host reuse one Image Factory artifact in the local datastore.
  talos_image_groups_by_proxmox_node = {
    for node_key, node in local.all_nodes : "${node.host_node}-${node.update ? local.update_image_id : local.image_id}" => {
      node_name    = node.host_node
      schematic_id = node.update ? local.update_schematic_id : local.schematic_id
      version      = node.update ? local.update_version : local.image_version
    }...
  }

  talos_images_by_proxmox_node = {
    for image_key, image_group in local.talos_image_groups_by_proxmox_node : image_key => image_group[0]
  }

  node_image_keys = {
    for node_key, node in local.all_nodes : node_key => "${node.host_node}-${node.update ? local.update_image_id : local.image_id}"
  }
}

data "http" "schematic_id" {
  # The factory returns a stable ID for the submitted schematic; OpenTofu uses
  # that ID for both the boot image and installer image references.
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.image_schematic

  request_headers = {
    "Content-Type" = "application/yaml"
  }
}

data "http" "updated_schematic_id" {
  # A separate update schematic lets future upgrades stage a different image
  # per node without replacing the baseline cluster image definition.
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic

  request_headers = {
    "Content-Type" = "application/yaml"
  }
}

resource "proxmox_download_file" "talos_nocloud_image" {
  for_each = local.talos_images_by_proxmox_node

  # Store the decompressed noCloud raw image as Proxmox ISO content because the
  # provider imports compressed raw cloud images from ISO storage by file ID.
  node_name    = each.value.node_name
  content_type = "iso"
  datastore_id = var.image.proxmox_image_datastore

  file_name               = "talos-${each.value.schematic_id}-${each.value.version}-${var.image.platform}-${var.image.arch}.img"
  url                     = "${var.image.factory_url}/image/${each.value.schematic_id}/${each.value.version}/${var.image.platform}-${var.image.arch}.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
}
