# Commit the stable backend shape for this stack while keeping bucket and
# account-specific details external to the repository.
terraform {
  backend "s3" {
    key    = "sk-home/home/wifi/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
