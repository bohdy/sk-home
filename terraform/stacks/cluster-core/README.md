# Cluster Core

This stack replaces the Pulumi `sk-k8s` domain with import-oriented Terraform.

It owns the live MetalLB, NFS provisioner, CoreDNS upstream config, cert-manager namespace, control-plane workloads, RBAC, issuers, and Traefik foundation objects. Import the existing Helm releases and Kubernetes resources before the first apply.

The cert-manager control plane is modeled as direct Kubernetes resources instead of a `helm_release` because the live installation was created by Pulumi with Helm-style labels but without a recoverable Helm release record. That keeps the running workloads importable without reinstalling or rotating the control plane.
