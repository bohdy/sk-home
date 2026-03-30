# Commit non-secret shared values here so Terraform and CI use the same k3s
# platform source of truth for the live environment.
project_name = "sk-home"
environment  = "home"

# Flatcar VM template created by scripts/create-flatcar-template.sh on the
# Proxmox host. Update this when upgrading to a new Flatcar release.
template_vm_id = 900

# k3s version pinned to the latest sysext-bakery release. Patch updates within
# the same minor track are handled automatically by systemd-sysupdate.
k3s_version = "v1.34.3+k3s1"

# --- Network (VLAN 20 servers subnet) ---
# TODO: fill in your actual VLAN 20 gateway and DNS server IPs.
network_gateway = "10.1.20.1"
dns_servers     = ["8.8.8.8"]

# --- Node inventory ---
# Add entries here to scale the cluster. Each key becomes the VM hostname.
# TODO: fill in actual IPs from your VLAN 20 servers subnet.
nodes = {
  k3s-server-1 = { vm_id = 110, ip = "10.1.20.11", role = "server" }
  k3s-agent-1  = { vm_id = 111, ip = "10.1.20.12", role = "agent" }
  k3s-agent-2  = { vm_id = 112, ip = "10.1.20.13", role = "agent" }
}
