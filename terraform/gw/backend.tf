terraform {
  backend "s3" {
    bucket = "sk-home"
    key    = "sk-home/home/gw/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    skip_region_validation = true

    endpoints = {
      s3 = "https://3b4089f3bd57e01c9d7c03c2587c3436.r2.cloudflarestorage.com"
    }
  }
}
