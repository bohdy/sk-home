# Observability Base

This component owns the shared `observability` namespace independently of every workload. Separating namespace ownership makes the bootstrap graph acyclic: Grafana's certificate can be issued after the namespace exists, and the metrics Helm release can then require the Ready certificate before mounting it.

The namespace retains its explicit privileged Pod Security Admission profile because node exporter and Vector require host namespaces or host log mounts. Individual workloads must still use the narrowest supported security context.

The base also owns the namespace `LimitRange` and `ResourceQuota`. The `LimitRange` supplies a 25 millicore/32 MiB request and a 250 millicore/256 MiB limit only when a chart-managed container omits its own values; explicit workload sizing remains authoritative. Per-container maxima stay above the current VMSingle envelope, and PVCs are bounded between 1 GiB and 150 GiB.

The aggregate quota permits 4 requested CPU cores, 6 GiB requested memory, 16 limited CPU cores, 20 GiB limited memory, 30 pods, 8 claims, and 300 GiB of requested storage. During sizing, the live namespace used 18 pods, 1.805 requested CPU cores, approximately 3.22 GiB requested memory, and 161 GiB of claims. The remaining allowance covers ordinary rolling updates and the planned SNMP and Proxmox exporters while preserving worker recovery headroom. Control-plane DaemonSet pods count toward the namespace totals even though they do not consume worker capacity.

Validate with:

```sh
kubectl kustomize kubernetes/flux/observability/base
kubectl kustomize kubernetes/flux/observability/base | kubectl apply --server-side --dry-run=server -f -
```

Do not remove the base component while any observability workload or retained claim exists. Namespace deletion is destructive and is never a routine rollback operation. If a later workload legitimately exceeds a guardrail, raise the smallest relevant quota or limit through a reviewed change; do not delete the controls during incident response.
