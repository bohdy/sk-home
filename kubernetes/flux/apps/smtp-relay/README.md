# SMTP relay

This component provides the Brother printer's outbound-only Postfix relay at `smtp.internal.bohdal.name:587` on the private Cilium VIP `10.1.30.58`. The LoadBalancer admits only the printer reservation `10.1.10.250/32`; Postfix additionally requires STARTTLS, the exact envelope sender `tiskarna@sk.bohdal.net`, at most five recipients, and at most twenty accepted messages per hour.

The relay forwards through `[smtp.seznam.cz]:587` with certificate-verified STARTTLS and SASL authentication. Seznam supplies the final DKIM signature. The deployment does not provide inbound public SMTP, local delivery, mailboxes, IMAP, webmail, spam filtering, or a general relay.

Before activation, publish the planned monitoring DMARC record at the Wedos-managed DNS provider: `_dmarc.sk.bohdal.net TXT "v=DMARC1; p=none"`. Keep the existing Seznam SPF include and `szn1`, `szn2`, and `szn3` DKIM CNAMEs intact, and verify them publicly before relying on delivery authentication.

## Secret bootstrap

Create Bitwarden item `SK-SMTP-RELAY` with only the Seznam SMTP password, then materialize it as `smtp-relay-upstream` after the namespace exists. Replace the local placeholder with the authorized Bitwarden item UUID; never commit the UUID if repository policy treats it as sensitive, and never print the password or generated Secret manifest.

```bash
set +x
set -o pipefail
umask 077
if ! smtp_relay_password="$(
  bws secret get <BITWARDEN_ITEM_ID> -o json \
    | jq -jre 'if (.value | type) == "string" and (.value | length) > 0 then .value else error("missing SMTP password") end'
)"; then
  printf '%s\n' 'Bitwarden SMTP password retrieval failed; no Kubernetes Secret was applied.' >&2
  exit 1
fi
if [[ -z "${smtp_relay_password}" ]]; then
  printf '%s\n' 'Bitwarden returned an empty SMTP password; no Kubernetes Secret was applied.' >&2
  exit 1
fi
# Stream the non-exported value through stdin so it is not written to disk or
# included in an environment block or process argument.
if ! printf '%s' "${smtp_relay_password}" \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n smtp-relay create secret generic smtp-relay-upstream \
      --from-file=password=/dev/stdin \
      --dry-run=client -o yaml \
  | kubectl --kubeconfig /tmp/sk-talos-kubeconfig apply -f -; then
  printf '%s\n' 'Kubernetes Secret creation failed; password was not displayed.' >&2
  exit 1
fi
unset smtp_relay_password
```

The Deployment reads the Secret through a file, and the Postfix image consumes it while generating its local SASL map. The map exists only on the writable container filesystem and is not sent to VictoriaLogs or exposed as a metric. Re-run the bootstrap command after rotating the Bitwarden value, then allow Flux to restart the pod.

## Deployment and validation

Allow the `smtp-relay` Flux Kustomization to reconcile after the external DNS and DHCP prerequisites are complete. Create the `smtp-relay-upstream` Secret after the namespace exists, then run the read-only preflight once the Flux Kustomization is Ready and the Deployment, Service, PVC, and Certificate are visible, before enabling the printer. It verifies the live Cilium pool, VIP availability, retained StorageClass, cert-manager issuer, split DNS, public DMARC, Flux reconciliation, Secret metadata, certificate readiness, and queue snapshot selection without reading Secret data.

```bash
mise run smtp-relay-preflight
```

```bash
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n smtp-relay get certificate,pod,service,pvc
kubectl --kubeconfig /tmp/sk-talos-kubeconfig -n smtp-relay get endpoints smtp-relay smtp-relay-metrics
```

From the printer, verify that `smtp.internal.bohdal.name` resolves to `10.1.30.58`, the certificate validates for that hostname, STARTTLS is required, SMTP AUTH is not requested, and a scan from `tiskarna@sk.bohdal.net` reaches the approved test recipients. Separately test rejection from another LAN address, a plaintext session, an unauthorized sender, a sixth recipient, and a source outside the printer reservation.

The exporter is scrape-filtered to aggregate queue and delivery families such as `postfix_showq_queue_depth`, `postfix_showq_message_age_seconds`, `postfix_smtp_messages_processed_total`, and `postfix_smtpd_messages_processed_total`; any future metadata-bearing exporter family is dropped at the scrape boundary. The pod is excluded from Vector collection, and local `/var/log` rotation keeps up to seven daily diagnostic rotations in ephemeral storage. The SMTP command filter adds `NOTIFY=NEVER` to every accepted recipient, so queue retention and failure counters remain available without returning external delivery-status messages to the unmonitored sender. Alert annotations intentionally contain no recipient, subject, message ID, message body, or credential.

The queue is the only persistent workload data and is deliberately excluded from backup selection with both the repository's exclusion label and the Velero exclusion annotation. This component declares no `VolumeSnapshot`; verify the live backup and snapshot controllers do not select `smtp-relay-queue` before production use.

## Security implementation note

The standard Postfix master process refuses to start unless it is UID 0, so a fully rootless Postfix Deployment is not technically possible with the selected maintained image. The one-shot init container also uses UID 0 to copy the image's `/etc` and `/scripts` defaults because startup rewrites `/etc/rsyslog.conf` and runs `chmod` on its scripts; those copied trees are the only generated system-configuration volumes. The Postfix container then uses the minimum image-required root control process with a read-only root filesystem, no API token, no privileged port, no privilege escalation, and only the capabilities needed for its privilege-separated child daemons. The metrics exporter runs as UID 65532. Replace these exceptions if a maintained rootless Postfix implementation becomes available, and re-run the SMTP acceptance tests before changing the image.

## Rollback

Stop new submissions by removing or suspending the Flux relay component before changing the printer. Restore the printer's previous SMTP settings and, if needed, restore the prior DHCP reservation and CoreDNS record through the same declarative workflow. Delete the unused `smtp-relay-upstream` Secret through the approved secret-management path after delivery investigation is complete. Keep the retained queue claim for manual delivery investigation; delete it only as an explicit follow-up after the seven-day diagnostic period and after confirming no queued mail remains.
