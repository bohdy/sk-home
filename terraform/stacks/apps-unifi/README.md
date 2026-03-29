# Apps UniFi

This stack replaces the Pulumi `sk-app-unifi` domain with import-oriented Terraform.

It owns the public Cloudflare hostname and Access application plus the live Kubernetes MongoDB, UniFi services, PVCs, deployments, and Traefik CRDs. Import the live objects before the first apply so persistent data and service exposure stay untouched.
