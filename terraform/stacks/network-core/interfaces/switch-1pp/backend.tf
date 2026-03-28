# Commit the full non-secret backend shape for the Switch 1PP interface root
# and keep only R2 credentials external to the repository.
terraform {
  backend "s3" {
    bucket = "sk-home"
    key    = "sk-home/home/network-core/interfaces/switch-1pp/terraform.tfstate"
    region = "auto"

    use_lockfile = true

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
