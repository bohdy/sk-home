# Cluster Core

This stack replaces the Pulumi `sk-k8s` domain with import-oriented Terraform.

It owns the live MetalLB, NFS provisioner, CoreDNS upstream config, cert-manager issuers, and Traefik foundation objects. Import the existing Helm releases and Kubernetes resources before the first apply.
