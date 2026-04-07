# Cluster Core k3s

This stack manages the shared Kubernetes platform layer for the new k3s cluster: MetalLB, NFS provisioner, CoreDNS upstream config, cert-manager, ACME issuers, and Traefik ingress. It intentionally mirrors the legacy `cluster-core` resources in a separate Terraform root and state key so migration can proceed without changing ownership of legacy k8s objects during cutover.
