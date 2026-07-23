terraform {
  # Keep RouterOS behavior aligned with the other active gateway stack.
  required_version = "1.12.1"

  required_providers {
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.1"
    }
  }
}
