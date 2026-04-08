# Keep the new-cluster DNS stack aligned with shared infrastructure metadata.
project_name = "sk-home"

environment = "home"

# Set this to a free MetalLB IP in the production-pool range before apply.
dns_ip = "10.1.30.254"

# Commit local DNS records as shared desired state so they are not hidden in UI.
custom_dns_records = {
  "unifi.sk.bohdal.name"   = "10.1.30.0"
  "traefik.sk.bohdal.name" = "10.1.30.0"
  "grafana.sk.bohdal.name" = "10.1.30.0"
}
