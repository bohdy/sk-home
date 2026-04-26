terraform {
  backend "s3" {
    # Store state in Cloudflare R2 so Terraform can coordinate changes without
    # keeping local state files on operator machines.
    bucket = "sk-home"
    key    = "sk-home/home/gw/terraform.tfstate"
    region = "auto"

    # Native lockfiles are enough for this repo's current single-state workflow.
    use_lockfile = true

    # skip_region_validation      = true
    # skip_credentials_validation = true
    # skip_metadata_api_check     = true
    # skip_requesting_account_id  = true

    # Cloudflare R2 implements the S3 API but not the full AWS identity and
    # regional metadata surface, so these AWS-specific validations must stay
    # disabled for backend initialization to succeed.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    endpoints = {
      # Keep the endpoint explicit so state access stays pinned to the intended
      # R2 account instead of relying on ambient AWS defaults.
      s3 = "https://3b4089f3bd57e01c9d7c03c2587c3436.r2.cloudflarestorage.com"
    }
  }
}
