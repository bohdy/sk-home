# UniFi controller

This component runs the restored self-hosted UniFi Network Application on Talos. It uses retained Synology iSCSI volumes, a pinned controller image matching the source backup, and MongoDB 8.0.28 with a dedicated database user authenticated through `admin` and authorized only for UniFi databases. `unifi-console` remains the private ClusterIP origin used by the Cloudflare Tunnel and by the TLS proxy upstream. `unifi-console-lan` publishes the canonical console hostname on Cilium LoadBalancer VIP `10.1.30.56:443` for `10.0.0.0/8` LAN clients, while split DNS resolves `unifi.bohdal.name` to that VIP. A dedicated unprivileged TLS proxy terminates the cert-manager-managed Let's Encrypt certificate on this LAN-only Service and relays only to the private controller origin; it keeps UniFi's self-hosted keystore and the Cloudflare origin path isolated from certificate rotation. The observability poller also uses `https://unifi.bohdal.name:443`, so its client-side certificate verification covers the cert-manager chain while the proxy's private upstream remains separately configured. `unifi-device-communication` is the fixed `10.1.30.1` Cilium LoadBalancer that carries only AP inform, STUN, and discovery traffic from `10.0.0.0/8`. Both LoadBalancer Services use `externalTrafficPolicy: Cluster` so the established control-plane BGP peers can advertise their VIPs and forward traffic to the controller on the worker; Cilium's explicit Service source-range policies enforce the home-network boundary before proxy traffic reaches the backend with the `world` identity. The public `unifi.bohdal.name` record is a Cloudflare Tunnel route protected by a single exact Google identity through Cloudflare Access. The proxy policy admits only the dedicated `observability/unifi-poller` ServiceAccount in addition to the existing LAN proxy path. Before each controller start, an init container idempotently writes `system_ip=10.1.30.1` to the persistent UniFi `system.properties` file. This follows UniFi's supported self-hosted setting for the address to which devices send inform traffic, while retaining all image-generated database configuration in the same file. MongoDB receives only the four capabilities needed for its first-run ownership setup and user drop. The LinuxServer controller uses its supported `s6` initialization context because its template rendering fails under no-new-privileges; the Pod-level RuntimeDefault seccomp and Cilium policy remain enforced. DNS allows the internal `unifi-mongodb.unifi.svc.cluster.local` service plus the external `trace.svc.ui.com` and `static.ui.com` endpoints; HTTPS egress is limited to the two external service names. Ubiquiti SSO is intentionally omitted, so the legacy GUI takes the local-admin path while Cloudflare Access continues to enforce the single Google identity at the Internet edge.

## Bootstrap

Before Flux can reconcile this component, create the two Kubernetes Secrets in namespace `unifi` from the dedicated Bitwarden items. The repository never stores either value.

```sh
set +x
export UNIFI_MONGODB_ROOT_PASSWORD="$(bws secret get 989143be-3e3e-4a66-b85c-b4910055b1bf -o json | jq -r .value)"
export UNIFI_MONGODB_APPLICATION_PASSWORD="$(bws secret get be72e505-dffe-41ac-aca8-b49100b86d86 -o json | jq -r .value)"

kubectl create namespace unifi --dry-run=client -o yaml | kubectl apply -f -
printf '%s' "${UNIFI_MONGODB_ROOT_PASSWORD}" | kubectl -n unifi create secret generic unifi-mongodb-auth --from-file=mongo-root-password=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -
printf '%s' "${UNIFI_MONGODB_APPLICATION_PASSWORD}" | kubectl -n unifi create secret generic unifi-mongodb-application-auth --from-file=application-password=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -

unset UNIFI_MONGODB_ROOT_PASSWORD UNIFI_MONGODB_APPLICATION_PASSWORD
```

## Restore and cutover

Create a fresh native `.unf` backup on the legacy controller and retain it outside Git. Reconcile this component, confirm both deployments are Ready, then port-forward `service/unifi-console` and restore the backup through UniFi's setup wizard. Verify the site, adopted devices, and controller-level SNMP setting before stopping the legacy controller.

Before reconciling the device service, stop the legacy controller and delete its `unifi-device-communication` LoadBalancer so only Talos can claim `10.1.30.1`. After reconciling the controller, trigger provisioning for every UniFi site so devices receive the configured `system_ip` inform destination. Verify that every adopted access point informs the Talos controller through the fixed VIP before applying the reviewed Cloudflare Tunnel, DNS, and Access configuration for `unifi.bohdal.name`. cert-manager issues `unifi-console-tls` with the production DNS-01 issuer, and the LAN proxy presents that trusted chain. The private Cloudflare Tunnel origin stays ClusterIP-only and continues to encrypt the hop to UniFi without exposing or relying on its self-hosted issuer.

Do not run both controllers against `10.1.30.1`, expose MongoDB, or copy the backup into Git, a Kubernetes ConfigMap, or a Secret.
