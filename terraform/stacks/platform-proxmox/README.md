# Platform Proxmox

This stack is the Terraform destination for the existing Pulumi `sk-infra` domain.

The stack root is committed now so the live Proxmox VM inventory, cloud-init files, and metrics-server wiring can be migrated into `sk-home` deliberately instead of staying implicit in Pulumi-only state.
