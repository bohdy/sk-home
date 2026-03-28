# Commit non-secret shared values here so Terraform and CI use the same
# network-core source of truth for the live environment.
project_name = "sk-home"

# Use the default home environment for the primary site.
environment = "home"
site_name   = "primary"

# Add optional non-sensitive metadata tags shared across network-core resources.
additional_tags = {
  owner = "home-lab"
}

# Point Terraform at the RouterOS HTTPS endpoints backed by `www-ssl`
# certificates so the provider can use the TLS-secured REST/API transport.
mikrotik_gw_hosturl         = "https://10.1.100.1"
mikrotik_switch_1pp_hosturl = "https://10.1.100.2"
mikrotik_switch_1np_hosturl = "https://10.1.100.3"
