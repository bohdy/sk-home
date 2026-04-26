# Point Terraform at the RouterOS HTTPS endpoint backed by `www-ssl`
# certificates so the provider can use the TLS-secured REST/API transport.
mikrotik_gw_hosturl = "https://10.1.100.1"

# Reuse the shared automation account until per-device credentials are
# intentionally split out.
mikrotik_username = "terraform"

# Keep the transitional TLS setting explicit until certificate trust is fully
# established for the RouterOS provider.
mikrotik_insecure = true
