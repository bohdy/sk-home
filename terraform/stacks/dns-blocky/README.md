# DNS Blocky

This stack replaces the Pulumi `sk-dns-blocky` domain with import-oriented Terraform.

Import the live namespace, service, PVC, ConfigMap, and DaemonSet before the first apply so the existing DNS IP and pods remain untouched.
