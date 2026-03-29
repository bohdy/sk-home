# Keep the imported UniFi stack aligned with the shared infrastructure project.
project_name = "sk-home"

# Preserve the public Cloudflare zone that serves the imported UniFi hostname.
cloudflare_zone_id = "48fce2129073417a753d224107dcefa1"

# Keep the imported tunnel target stable while plans remain read-only in CI.
cloudflare_tunnel_id = "1c1c10b9-731f-4c0a-9b89-c5d2f45066d0"

# Reuse the shared imported Access policy so plan output stays convergent.
shared_access_policy_id = "449830db-baee-4d1f-a85a-c1ffb82a1147"
