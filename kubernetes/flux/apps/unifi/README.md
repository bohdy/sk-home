# UniFi controller

This component runs the restored self-hosted UniFi Network Application on Talos. It uses retained Synology iSCSI volumes, a pinned controller image matching the source backup, and MongoDB 8.0.28 with a dedicated database user authenticated through `admin` and authorized only for UniFi databases. `unifi-console` remains a private ClusterIP service. `unifi-device-communication` is the fixed `10.1.30.1` Cilium LoadBalancer that carries only AP inform, STUN, and discovery traffic from `10.0.0.0/8`. MongoDB receives only the four capabilities needed for its first-run ownership setup and user drop. The LinuxServer controller uses its supported `s6` initialization context because its template rendering fails under no-new-privileges; the Pod-level RuntimeDefault seccomp and Cilium policy remain enforced.

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

Before reconciling the device service, stop the legacy controller and delete its `unifi-device-communication` LoadBalancer so only Talos can claim `10.1.30.1`. Verify that every adopted access point informs the Talos controller through the fixed VIP before adding the Cloudflare tunnel route, DNS record, or Cloudflare Access application for `unifi.bohdal.name`.

Do not run both controllers against `10.1.30.1`, expose MongoDB, or copy the backup into Git, a Kubernetes ConfigMap, or a Secret.
