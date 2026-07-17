# VictoriaLogs

This component installs the official `victoria-logs-single` chart 0.13.9 with VictoriaLogs v1.52.0. It runs one ClusterIP-only instance with 30-day age retention and a retained 50 GiB `synology-iscsi-retain` claim.

The StatefulSet-generated claim is retained by Kubernetes by default and carries `helm.sh/resource-policy: keep` as an explicit retention marker. Failed-install remediation and intentional release removal must preserve log data. Storage deletion always requires a separate explicit decision.

The chart publishes a `VMServiceScrape` for self-monitoring and its official Grafana dashboard. Vector is deliberately disabled here and is deployed as a separate reviewed collector component.

Grafana installs the signed `victoriametrics-logs-datasource` plugin at pinned version 0.29.0 and provisions the internal `http://victoria-logs.observability.svc.cluster.local.:9428` data source from the metrics release.

## Validation

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get helmrelease victoria-logs
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get pods,pvc,vmservicescrape
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability port-forward service/victoria-logs 9428:9428
```

Acceptance requires the claim and workload to become Ready, the live command line to contain 30-day and 85% retention limits, self-metrics to reach VMSingle with stable labels, Grafana to load plugin 0.29.0, and a synthetic log to survive a VictoriaLogs pod recreation before the test record expires naturally.
