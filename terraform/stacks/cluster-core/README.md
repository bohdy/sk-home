# Cluster Core

This stack replaces the Pulumi `sk-k8s` domain with import-oriented Terraform.

It owns the live MetalLB, NFS provisioner, CoreDNS upstream config, cert-manager namespace and issuers, and Traefik foundation objects. Import the existing Helm releases and Kubernetes resources before the first apply.

The cert-manager control-plane workloads are currently out of scope for this stack because the live installation was created by Pulumi with Helm-style labels but without a recoverable Helm release record. Preserve the running control plane in place until a follow-up migration models those resources directly.
