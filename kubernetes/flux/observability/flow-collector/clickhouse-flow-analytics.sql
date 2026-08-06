-- Centralize the LAN policy used by Grafana host selection and flow panels.
-- These CIDRs mirror the routed VLAN inventory in
-- terraform/network/gw/interfaces/vlans.auto.tfvars. The WAN transit subnet
-- is intentionally absent even though it also uses RFC1918 address space.
CREATE OR REPLACE VIEW flows.flow_analytics AS
SELECT
    flow.*,
    startsWith(src_addr, '10.1.10.')
        OR startsWith(src_addr, '10.1.20.')
        OR startsWith(src_addr, '10.1.100.')
        OR startsWith(src_addr, '10.1.101.')
        OR startsWith(src_addr, '10.1.102.') AS src_internal,
    startsWith(dst_addr, '10.1.10.')
        OR startsWith(dst_addr, '10.1.20.')
        OR startsWith(dst_addr, '10.1.100.')
        OR startsWith(dst_addr, '10.1.101.')
        OR startsWith(dst_addr, '10.1.102.') AS dst_internal
FROM flows.flow AS flow;
