# Overlay

This stack replaces the Pulumi `sk-tailscale` domain with import-oriented Terraform.

It owns the live Kubernetes namespace, secret, service account, RBAC, and deployment for the existing subnet router. Import the existing objects before the first apply so route advertisement and stored node state remain uninterrupted.
