terraform {
  # The stack uses the built-in terraform_data resource and no third-party
  # provider, but all stacks still use the repository's pinned OpenTofu line.
  required_version = "1.12.1"
}
