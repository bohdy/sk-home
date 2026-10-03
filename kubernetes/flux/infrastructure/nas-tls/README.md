# NAS TLS delivery

This component obtains `nas.bohdal.name` through the existing production DNS-01 `ClusterIssuer`, then stages a pinned, in-place certificate delivery path to DSM at `10.1.100.10:5001`. It creates no Service, Ingress, LoadBalancer VIP, DNS record, DHCP lease, gateway rule, or Kubernetes API credential.

The `nas-tls-issue`, `nas-tls-bootstrap`, and `nas-tls-delivery` Flux children are all suspended when introduced. Enable them independently after reviewing the relevant gate: issue the source certificate first, establish the first DSM import through an independently trusted operator channel, pin the existing DSM certificate id in `reconciler-config.json`, and only then enable the one-shot bootstrap and recurring delivery stages. The reconciler always uses strict system-trust TLS with SNI and hostname `nas.bohdal.name`; it has no HTTP, expiry-ignore, fingerprint-only, or insecure fallback.

The operator must create Secret `nas-tls-dsm-auth` in namespace `nas-tls` with keys `username` and `password` through the repository's approved Bitwarden stdin procedure. The item value is an operator-approved JSON object with those two keys; replace `<operator-approved-item-id>` below with the real private inventory id and keep shell tracing disabled:

```sh
set +x
bws secret get <operator-approved-item-id> -o json \
  | jq -r '.value | fromjson | {apiVersion:"v1",kind:"Secret",metadata:{name:"nas-tls-dsm-auth",namespace:"nas-tls"},type:"Opaque",stringData:{username:.username,password:.password}}' \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -
```

The pipeline sends the value through stdin and emits no secret-bearing argument or output; stop if the item is not exactly that JSON contract. The source Secret `nas-tls` is owned by cert-manager. The DSM principal must have the administrator-class certificate-import permission required by the DSM API; this repository does not claim a narrower privilege is sufficient. No credential is committed, passed in argv or environment, or printed by the reconciler.

The reconciler validates the projected cert/key pair with `SSLContext.load_cert_chain`, performs a bounded loopback full-chain handshake using system trust and the canonical hostname, checks peer-decoded dates and remaining lifetime, and captures one immutable Secret projection before upload. DSM discovery is constrained to the reviewed API paths and versions. The selected certificate must have exactly one matching description and the operator-pinned stable id. Import preserves the id, description, `is_default`, and complete service assignment list; a changed binding, duplicate target, unknown response shape, redirect, upload failure, or post-import served-leaf mismatch fails closed. Session material is kept in memory and sent only through the DSM cookie/header contract; public API selectors may appear in the URL, never passwords, SIDs, or SynoTokens.

The bootstrap child is a separately approved one-shot run of the same strict reconciler. The existing expired or wrong-name DSM certificate cannot satisfy its TLS precondition; use an independently trusted operator channel to repair that precondition before enabling the child, then record the exact existing DSM stable id in the reviewed ConfigMap. The current staged repository has not performed that live preflight or claimed activation acceptance. Rollback preserves the selected certificate id and service bindings: suspend the delivery and bootstrap children, retain the cert-manager Secret and DSM certificate, and correct the reviewed source/config before a new run. Do not delete the selected DSM certificate or rebind services as a rollback.

The monitoring child adds a strict HTTPS blackbox probe for the unauthenticated DSM API-info path, an additive Cilium rule for only `10.1.100.10/32:5001`, served-leaf expiry alerts, readiness and missing-probe alerts, and KSM-based CronJob failure/last-success staleness alerts. It remains independently suspended until delivery is intentionally activated.

The API path and session handling are based on the [official Synology WebAPI guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/Calendar/All/enu/Calendar_API_Guide_enu.pdf), the maintained [Synology certificate provider implementation](https://github.com/batonogov/terraform-provider-synology-dsm/blob/main/internal/client/certificate.go), and the maintained [acme.sh DSM deploy hook](https://github.com/acmesh-official/acme.sh/blob/master/deploy/synology_dsm.sh). The provider's state boundary is unsuitable here because it retains private keys in state; this narrow mounted-Secret reconciler is the explicitly documented exception and must not be mixed with provider ownership.
