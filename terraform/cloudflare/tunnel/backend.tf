terraform {
  backend "s3" {
    # Keep the shared tunnel in an independent state so application routes can
    # evolve without coupling Cloudflare control-plane state to Talos VMs.
    bucket = "sk-home"
    key    = "sk-home/home/cloudflare/tunnel/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    # Cloudflare R2 implements the S3 data plane but not AWS account metadata.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    endpoints = {
      s3 = "https://3b4089f3bd57e01c9d7c03c2587c3436.r2.cloudflarestorage.com"
    }
  }
}
