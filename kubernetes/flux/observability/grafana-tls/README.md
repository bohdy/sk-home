# Grafana TLS

This component requests the production certificate that Grafana will serve directly. It covers canonical name `grafana.bohdal.name` and explicit LAN alias `grafana.internal.bohdal.name`, writes standard TLS keys to Secret `grafana-tls` in namespace `observability`, and rotates its ECDSA private key on every issuance.

The separate Flux Kustomization depends on the production ClusterIssuer and the base component that owns the namespace. The metrics component in turn depends on this certificate. Keeping those responsibilities separate prevents the Grafana Helm release from mounting a Secret that does not exist yet and keeps fresh-cluster bootstrap acyclic.

## Validation

Render and validate the resource before publishing:

```sh
kubectl kustomize kubernetes/flux/observability/grafana-tls
kubectl kustomize kubernetes/flux/observability/grafana-tls | kubectl apply --server-side --dry-run=server -f -
```

Live acceptance requires Flux Ready at the merged Git revision, Certificate condition `Ready=True`, a current revision Secret of type `kubernetes.io/tls` containing only `tls.crt` and `tls.key`, both requested DNS names in the issued certificate, and no certificate value printed or committed.

Routine rollback removes or suspends `observability-grafana-tls`. Keep Secret `grafana-tls` while Grafana references it; remove the Secret only after the HTTPS listener is reverted.
