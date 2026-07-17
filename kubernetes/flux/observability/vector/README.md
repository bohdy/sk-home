# Vector collector

This component installs official Vector chart 0.57.0 as an Agent DaemonSet. Each pod reads only its node's Kubernetes container logs, enriches them with stable cluster and workload fields, and sends newline-delimited JSON to the internal VictoriaLogs service.

Pods annotated `vector.dev/exclude: "true"` are removed before normalization or buffering. Current Vector source-side exclusion uses the same key as a label, so Vector carries both the label and annotation itself to prevent collector logs from forming an ingestion loop while preserving the repository's annotation contract for other workloads.

Each node uses `/var/lib/vector` for a bounded 1 GiB disk buffer. The sink blocks producers when the buffer is full, preserving TCP-like delivery semantics inside the pipeline; source files remain available for Vector checkpoints and retry. Vector internal metrics expose drops, errors, retries, and buffer pressure through a `VMPodScrape`.

The official distroless image declares UID 0, and the Agent needs write access to its node-local hostPath checkpoint and buffer directory. The container therefore runs as UID 0 but receives no added capabilities, cannot escalate privileges, uses a read-only root filesystem, and uses RuntimeDefault seccomp.

The same DaemonSet accepts RFC syslog on TCP and UDP port 514 through fixed Cilium LoadBalancer VIP `10.1.30.54`. The Service allows `10.0.0.0/8` and uses `externalTrafficPolicy: Local` to preserve the original sender address. TCP is preferred for devices that support it; UDP remains available for compatibility.

Socket input is parsed fallibly. Every record retains its raw message, transport, sender, receipt timestamp, and `parse_status`; malformed input is stored as `unparsed` instead of being dropped. Parsed sender timestamps are retained separately, while the trustworthy Vector receipt time controls storage ordering.

TCP and UDP syslog are throttled independently at 1,000 events per second for each preserved sender address. This leaves a tenfold reserve above the initial 100 events/second planning load while bounding a runaway device. Vector exports aggregate discarded-event metrics for alerting but omits sender keys from those metrics to avoid attacker-controlled cardinality.

Talos service and kernel logs use JSON lines over TCP port 6051 on the same VIP. Vector parses that stream separately from RFC syslog, preserves malformed records, assigns `talos_stream` as `service`, `kernel`, or `unknown`, and keeps Talos' sender timestamp separate from its receipt timestamp. The Talos OpenTofu stack supplies a stable node tag for service logs; kernel records fall back to the preserved sender address when they do not contain that tag.

## Validation

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get helmrelease vector
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get daemonset,pods,vmpodscrape
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability logs daemonset/vector
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get service syslog
talosctl --talosconfig /tmp/sk-talos-talosconfig -n 10.1.20.41 get machineconfig -o yaml
```

Acceptance requires one Ready pod per node with no repeated restarts, valid Vector configuration, Kubernetes records from every node in VictoriaLogs, no Vector self-records, annotation exclusion, stable stream fields, retained checkpoints across pod recreation, healthy sink metrics, and no dropped events. Syslog acceptance additionally requires LAN reachability on TCP and UDP 514, original sender preservation, valid RFC parsing, malformed-record retention, and end-to-end persistence. Talos acceptance requires service and kernel records from every node on TCP 6051, stable node identity, correct stream classification, receipt and sender timestamps, malformed-record retention, and no unexpected machine reboot.
