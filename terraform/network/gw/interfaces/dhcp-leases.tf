# RouterOS exposes dynamic-to-static conversion only as the `make-static`
# command, which the pinned provider cannot model. Keep that narrowly scoped
# break-glass command Terraform-owned, then import the resulting static lease.
resource "terraform_data" "make_brother_printer_lease_static" {
  input = {
    lease_id = "*135B"
  }

  provisioner "local-exec" {
    # The command reads credentials from process environment variables so no
    # secret is rendered into plans, state, or the checked-in script.
    command = "sh '${path.module}/make-dhcp-lease-static.sh'"

    environment = {
      MIKROTIK_API_BASE_URL = var.mikrotik_gw_hosturl
      MIKROTIK_LEASE_ID     = self.input.lease_id
      MIKROTIK_PASSWORD     = var.mikrotik_password
      MIKROTIK_USERNAME     = var.mikrotik_username
    }
  }
}

# Adopt the Brother printer's newly static lease so future changes remain in
# the provider-managed resource rather than in an imperative helper.
import {
  to = routeros_ip_dhcp_server_lease.brother_printer
  id = "*135B"
}

resource "routeros_ip_dhcp_server_lease" "brother_printer" {
  provider = routeros.gw

  address     = "10.1.10.13"
  mac_address = "3C:2A:F4:F4:B6:7F"
  client_id   = "1:3c:2a:f4:f4:b6:7f"
  server      = "server10"
  comment     = "Brother printer"

  depends_on = [terraform_data.make_brother_printer_lease_static]
}

# Apply the same documented RouterOS conversion to the APC card. The data
# resource runs once; its script exits successfully when the lease is already
# static, making recovery from a partial apply safe.
resource "terraform_data" "make_apc_ups_lease_static" {
  input = {
    lease_id = "*158A"
  }

  provisioner "local-exec" {
    command = "sh '${path.module}/make-dhcp-lease-static.sh'"

    environment = {
      MIKROTIK_API_BASE_URL = var.mikrotik_gw_hosturl
      MIKROTIK_LEASE_ID     = self.input.lease_id
      MIKROTIK_PASSWORD     = var.mikrotik_password
      MIKROTIK_USERNAME     = var.mikrotik_username
    }
  }
}

# The APC network management card is always-on infrastructure, so adopt its
# resulting static reservation for declarative lifecycle management.
import {
  to = routeros_ip_dhcp_server_lease.apc_ups
  id = "*158A"
}

resource "routeros_ip_dhcp_server_lease" "apc_ups" {
  provider = routeros.gw

  address     = "10.1.10.43"
  mac_address = "60:45:2E:D8:B7:3D"
  client_id   = "1:60:45:2e:d8:b7:3d"
  server      = "server10"
  comment     = "APC UPS"

  depends_on = [terraform_data.make_apc_ups_lease_static]
}
