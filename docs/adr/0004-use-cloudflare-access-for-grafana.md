# Use Cloudflare Access for Grafana

Grafana's canonical hostname will be protected by Cloudflare Access even for LAN users, with Cloudflare Tunnel publishing the service only after the Access application and policy exist. A separate internal break-glass hostname may route directly through LAN DNS and an internal proxy or service path, but it must keep Grafana login enabled and stay limited to trusted networks so split DNS does not silently bypass the primary access-control boundary.
