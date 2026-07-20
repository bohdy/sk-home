# Observability Base

This component owns the shared `observability` namespace independently of every workload. Separating namespace ownership makes the bootstrap graph acyclic: Grafana's certificate can be issued after the namespace exists, and the metrics Helm release can then require the Ready certificate before mounting it.

The namespace retains its explicit privileged Pod Security Admission profile because node exporter and Vector require host namespaces or host log mounts. Individual workloads must still use the narrowest supported security context.

Validate with:

```sh
kubectl kustomize kubernetes/flux/observability/base
kubectl kustomize kubernetes/flux/observability/base | kubectl apply --server-side --dry-run=server -f -
```

Do not remove the base component while any observability workload or retained claim exists. Namespace deletion is destructive and is never a routine rollback operation.
