# Adopt the existing RouterOS default community after its break-glass
# remediation so all subsequent ACL and credential changes remain declarative.
import {
  to = routeros_snmp_community.observability_v2
  id = "*0"
}

resource "routeros_snmp_community" "observability_v2" {
  provider = routeros.gw

  name         = var.snmp_v2_community
  addresses    = ["10.0.0.0/8"]
  security     = "none"
  read_access  = true
  write_access = false
  disabled     = false
  comment      = "sk-talos SNMPv2c compatibility"
}

# RouterOS exposes the SNMPv3 security name through the same community model.
# SHA1 and AES are the strongest authPriv combination supported by this device;
# write access and traps remain outside the monitoring identity's scope.
import {
  to = routeros_snmp_community.observability_v3
  id = "*2"
}

resource "routeros_snmp_community" "observability_v3" {
  provider = routeros.gw

  name                    = var.snmp_v3_username
  addresses               = ["10.0.0.0/8"]
  security                = "private"
  authentication_protocol = "SHA1"
  authentication_password = var.snmp_v3_auth_password
  encryption_protocol     = "AES"
  encryption_password     = var.snmp_v3_priv_password
  read_access             = true
  write_access            = false
  disabled                = false
  comment                 = "sk-talos SNMPv3 authPriv"
}
