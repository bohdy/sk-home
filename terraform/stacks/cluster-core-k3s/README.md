# Cluster Core k3s

This stack manages the shared Kubernetes platform layer for the new k3s cluster: MetalLB, NFS provisioner, CoreDNS upstream config, cert-manager, ACME issuers, and Traefik ingress. It intentionally mirrors the legacy `cluster-core` resources in a separate Terraform root and state key so migration can proceed without changing ownership of legacy k8s objects during cutover.

The Traefik release in this stack intentionally does not expose DNS entrypoints on port `53`, because external DNS ownership for the new cluster is delegated to the dedicated [`dns-blocky-k3s`](../dns-blocky-k3s) stack.
