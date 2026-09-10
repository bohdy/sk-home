terraform {
  backend "s3" {
    # Keep storage state separate from VM and network state so a storage
    # reconciliation can never consume an unrelated stack's lock or plan.
    bucket = "sk-home"
    key    = "sk-home/home/proxmox/storage/terraform.tfstate"
    region = "auto"

    # Cloudflare R2 implements the S3 API but not the AWS regional metadata
    # surface, so these checks must stay disabled for backend initialization.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true

    endpoints = {
      # Pin state access to the repository's existing R2 endpoint instead of
      # relying on ambient AWS configuration.
      s3 = "https://3b4089f3bd57e01c9d7c03c2587c3436.r2.cloudflarestorage.com"
    }
  }
}
