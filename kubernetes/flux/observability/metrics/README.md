# Metrics Stack

This component installs the official `victoria-metrics-k8s-stack` chart 0.86.1 through Flux. It deploys VictoriaMetrics v1.147.0, the VictoriaMetrics operator, VMSingle, VMAgent, VMAlert, Alertmanager, Grafana, kube-state-metrics, node exporter, Kubernetes scrape resources, starter rules, and dashboards.

Stable labels are `cluster="sk-talos"` and `site="sk"`. General collection runs every 30 seconds. VMSingle retains raw metrics for one year on a retained 100 GiB Synology iSCSI claim.

Grafana and Alertmanager use retained 10 GiB and 1 GiB claims respectively. All services remain cluster-internal in this change; TLS and the fixed LAN/Cloudflare route are separate acceptance-gated changes.

## Grafana credential

Bitwarden Secrets Manager item `SK-TALOS-GRAFANA-ADMIN-PASSWORD` (`6e37471a-b993-4700-907e-b48a009f9c41`) contains only the administrator password.

Create the Kubernetes Secret before Flux reconciles this component:

```bash
export GRAFANA_ADMIN_PASSWORD="$(bws secret get 6e37471a-b993-4700-907e-b48a009f9c41 -o json | jq -r .value)"

kubectl --kubeconfig /tmp/sk-talos-kubeconfig create namespace observability --dry-run=client -o yaml \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -

unset GRAFANA_ADMIN_PASSWORD
```

Keep shell tracing disabled while the password is present. Restart Grafana after rotating the Secret.

## Validation

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get pods,pvc
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get vmsingle,vmagent,vmalert,vmalertmanager
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability port-forward service/metrics-grafana 3000:80
```

Acceptance requires all retained claims to bind, every component to become Ready without repeated restarts, VMAgent targets to be healthy, samples to enter VMSingle with both global labels, Grafana to query the provisioned VictoriaMetrics data source, and a persistence marker to survive a Grafana pod recreation.

Rollback suspends or reverts the Flux component while preserving all retained claims. Never delete observability PVCs, released PVs, or Synology LUNs as routine rollback.
