# sk-home

This context defines the operational language for the sk-home infrastructure learning repository.

## Language

**Active Stack**:
An infrastructure stack that is retained in the repository and expected to participate in the current infrastructure workflow.
_Avoid_: Legacy stack, Terraform-era stack

**Home Infrastructure Observability**:
A cluster-hosted observability platform that collects and correlates operational signals from active home infrastructure, including Kubernetes workloads, cluster nodes, network devices, and core services.
_Avoid_: Monitoring stack, logging stack, observability stack

**Retired Stack**:
An infrastructure stack removed from the repository because it is no longer part of the current operating model.
_Avoid_: Legacy stack, reference stack
