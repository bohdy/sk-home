# Metrics Stack

This component installs the official `victoria-metrics-k8s-stack` chart 0.86.1 through Flux. It deploys VictoriaMetrics v1.147.0, the VictoriaMetrics operator, VMSingle, VMAgent, VMAlert, Alertmanager, Grafana, kube-state-metrics, node exporter, Kubernetes scrape resources, starter rules, and dashboards.

Stable labels are `cluster="sk-talos"` and `site="sk"`. General collection runs every 30 seconds. VMSingle retains raw metrics for one year on a retained 100 GiB Synology iSCSI claim.

Grafana and Alertmanager use retained 10 GiB and 1 GiB claims respectively. Grafana's Helm-managed claim carries the `helm.sh/resource-policy: keep` annotation so failed-install remediation and intentional Helm removal preserve it.

Grafana terminates HTTPS directly with cert-manager Secret `grafana-tls`. Cilium exposes it to `10.0.0.0/8` on fixed LoadBalancer VIP `10.1.30.55`; the Service forwards TCP 443 to Grafana's HTTPS listener on port 3000. Internal split DNS maps canonical name `grafana.bohdal.name` and explicit LAN alias `grafana.internal.bohdal.name` to the VIP. Grafana enforces the canonical root URL, keeps its own login enabled, and has no ingress-controller dependency. Its generated VMServiceScrape also uses HTTPS and verifies the public certificate against `grafana.bohdal.name`.

Talos does not expose scheduler or controller-manager metric endpoints, so their default alert and recording-rule groups are explicitly disabled. Alertmanager groups by alert, cluster, and site with bounded delivery intervals. It inhibits lower severities for the same alert and contains dependency rules for future SNMP interface symptoms and VictoriaLogs-induced Vector buffer pressure. The stack's default data sources already expose Alertmanager in Grafana for silence management without a duplicate extra definition. Notification receivers remain the `blackhole` until their Bitwarden-backed Telegram and Discord credentials are bootstrapped.

The shared namespace explicitly uses privileged Pod Security Admission because node exporter requires host namespaces and host mounts, and the later Vector DaemonSet requires host log mounts. This exception does not make every workload privileged; chart and local workload security contexts must still grant only the access each component requires.

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
curl --fail --show-error --silent https://grafana.bohdal.name/api/health
```

Acceptance requires all retained claims to bind, every component to become Ready without repeated restarts, VMAgent targets to be healthy, samples to enter VMSingle with both global labels, Grafana to query the provisioned VictoriaMetrics data source, and a persistence marker to survive a Grafana pod recreation. LAN exposure additionally requires Cilium to allocate only `10.1.30.55`, Blocky to return both committed names and the reverse record, a browser-trusted TLS chain with both names, an authenticated health response through the VIP, and rejection of plaintext HTTP.

Rollback suspends or reverts the Flux component while preserving all retained claims. The keep annotation causes Helm to report the preserved Grafana PVC as an intentionally skipped resource during uninstall. Never delete observability PVCs, released PVs, or Synology LUNs as routine rollback.
