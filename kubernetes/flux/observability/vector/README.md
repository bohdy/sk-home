# Vector collector

This component installs official Vector chart 0.57.0 as an Agent DaemonSet. Each pod reads only its node's Kubernetes container logs, enriches them with stable cluster and workload fields, and sends newline-delimited JSON to the internal VictoriaLogs service.

Pods annotated `vector.dev/exclude: "true"` are removed before normalization or buffering. Current Vector source-side exclusion uses the same key as a label, so Vector carries both the label and annotation itself to prevent collector logs from forming an ingestion loop while preserving the repository's annotation contract for other workloads.

Each node uses `/var/lib/vector` for a bounded 1 GiB disk buffer. The sink blocks producers when the buffer is full, preserving TCP-like delivery semantics inside the pipeline; source files remain available for Vector checkpoints and retry. Vector internal metrics expose drops, errors, retries, and buffer pressure through a `VMPodScrape`.

The official distroless image declares UID 0, and the Agent needs write access to its node-local hostPath checkpoint and buffer directory. The container therefore runs as UID 0 but receives no added capabilities, cannot escalate privileges, uses a read-only root filesystem, and uses RuntimeDefault seccomp.

The same DaemonSet accepts RFC syslog on TCP and UDP port 514 through fixed Cilium LoadBalancer VIP `10.1.30.54`. The Service allows `10.0.0.0/8` and uses `externalTrafficPolicy: Local` to preserve the original sender address. TCP is preferred for devices that support it; UDP remains available for compatibility.

Socket input is parsed fallibly. Every record retains its raw message, transport, sender, receipt timestamp, and `parse_status`; malformed input is stored as `unparsed` instead of being dropped. Parsed sender timestamps are retained separately, while the trustworthy Vector receipt time controls storage ordering.

## Validation

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get helmrelease vector
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get daemonset,pods,vmpodscrape
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability logs daemonset/vector
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n observability get service syslog
```

Acceptance requires one Ready pod per node with no repeated restarts, valid Vector configuration, Kubernetes records from every node in VictoriaLogs, no Vector self-records, annotation exclusion, stable stream fields, retained checkpoints across pod recreation, healthy sink metrics, and no dropped events. Syslog acceptance additionally requires LAN reachability on TCP and UDP 514, original sender preservation, valid RFC parsing, malformed-record retention, and end-to-end persistence.
