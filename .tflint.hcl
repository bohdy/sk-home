# Keep local lint output compact enough for commit-time use while still making
# TFLint traverse nested module calls when stacks begin consuming them.
config {
  format              = "compact"
  call_module_type    = "all"
  force               = false
  disabled_by_default = false
}

# Catch Terraform blocks that declare providers but never consume them.
rule "terraform_unused_required_providers" {
  enabled = true
}

# Catch variables, locals, outputs, and data declarations that are no longer
# referenced after a refactor.
rule "terraform_unused_declarations" {
  enabled = true
}

# Keep comment syntax consistent so Terraform comments remain readable and
# unambiguous across stacks.
rule "terraform_comment_syntax" {
  enabled = true
}

# Prevent reintroducing legacy interpolation-only expressions that modern
# Terraform no longer needs.
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Keep deprecated collection indexing syntax out of new changes.
rule "terraform_deprecated_index" {
  enabled = true
}

# Require explicit types on variables so stack inputs stay predictable.
rule "terraform_typed_variables" {
  enabled = true
}

# Keep the required Terraform version explicit in every root module.
rule "terraform_required_version" {
  enabled = true
}
