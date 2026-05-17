resource "proxmox_download_file" "ubuntu_server_resolute_image" {
  # Pin the Ubuntu cloud image to an immutable dated build so the checksum and
  # downloaded bytes move together only during an intentional image upgrade.
  content_type       = "import"
  overwrite          = true 
  datastore_id       = "local"
  file_name          = "resolute-server-cloudimg-amd64.qcow2"
  node_name          = "pve"
  url                = "https://cloud-images.ubuntu.com/resolute/20260421/resolute-server-cloudimg-amd64.img"
  checksum           = "8ed228c9f08a50122fa72307623d9f88d9209ba26e7e849edd584fa675e34863"
  checksum_algorithm = "sha256"
}

resource "proxmox_download_file" "flatcar_image" {
  # Pin the Flatcar production image for reproducible cluster rebuilds instead
  # of following the mutable "current" release pointer.
  content_type       = "import"
  overwrite          = true 
  datastore_id       = "local"
  file_name          = "flatcar_production_proxmoxve_image.raw"
  node_name          = "pve"
  url                = "https://stable.release.flatcar-linux.net/amd64-usr/4593.2.1/flatcar_production_proxmoxve_image.img"
  checksum           = "eb81621cd79e4b994ba9f94d7641b9c4719d9ccb30f4dae3dcf3cb05a9bd23e793682b289349423d195eebdc1a56b9003f4ace4ffc48fa45f338607145caeabe"
  checksum_algorithm = "sha512"
}
