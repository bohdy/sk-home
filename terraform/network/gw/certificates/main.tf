# Register one durable ACME account so certificate issuance and renewal can be
# traced by Let's Encrypt without committing its private account key.
resource "acme_registration" "gateway" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email
}

# Generate the ACME-account key inside OpenTofu. It is sensitive state in the
# encrypted backend and is never emitted as an output, log line, or artifact.
resource "tls_private_key" "acme_account" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# DNS-01 preserves Cloudflare proxying and never exposes RouterOS management
# ports to the Internet. OpenTofu renews when fewer than 30 days remain.
resource "acme_certificate" "gateway" {
  account_key_pem    = acme_registration.gateway.account_key_pem
  common_name        = "gw.bohdal.name"
  key_type           = "P256"
  min_days_remaining = 30

  # The authoritative dns.bohdal.name server publishes Cloudflare-created TXT
  # records just after the provider's default two-minute check window. Wait a
  # conservative five minutes before asking Let's Encrypt to validate DNS-01.
  propagation_wait = 300

  dns_challenge {
    provider = "cloudflare"

    config = {
      CF_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

# Keep the certificate and temporary-file names stable so the replacement
# script touches only the objects this stack owns.
locals {
  gateway_certificate_name        = "letsencrypt-gateway"
  gateway_issuer_certificate_name = "letsencrypt-gateway-issuer"
  gateway_leaf_file_name          = "tf-gateway-leaf.pem"
  gateway_issuer_file_name        = "tf-gateway-issuer.pem"
  gateway_key_file_name           = "tf-gateway-key.pem"
}

# The RouterOS provider cannot reliably find a certificate after REST import:
# RouterOS does not return the requested name. Use the documented REST file and
# execute endpoints for this single unsupported provider operation. OpenTofu
# still owns renewal cadence and reruns this installer only when the leaf
# certificate changes.
resource "terraform_data" "install_gateway_certificate" {
  input = local.gateway_certificate_name

  # Store only a digest in the plan and state trigger; the PEM and private key
  # remain provisioner environment values and never appear in plan output.
  triggers_replace = [sha256(acme_certificate.gateway.certificate_pem)]

  provisioner "local-exec" {
    # The certificate workflow runs Linux self-hosted runners. Bash keeps the
    # request construction fail-closed and prevents accidental word splitting.
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      set -euo pipefail
      routeros_url="${trimsuffix(var.mikrotik_hosturl, "/")}/rest"
      curl_options=(--fail --silent --show-error --user "$ROUTEROS_USERNAME:$ROUTEROS_PASSWORD" --header "content-type: application/json")
      if [ "$ROUTEROS_INSECURE" = "true" ]; then
        curl_options+=(--insecure)
      fi

      write_file() {
        local file_name="$1"
        local file_contents="$2"
        local payload
        local response
        # RouterOS accepts file creation through REST, but this device rejects
        # contents in the REST PUT body. Use the documented execute endpoint to
        # create an empty file and set its contents through the file menu.
        payload="$(jq -cn \
          --arg name "$file_name" \
          --arg contents "$file_contents" \
          'def routeros_escape:
             gsub("\\\\"; "\\\\\\\\")
             | gsub("\\\""; "\\\\\\\"")
             | gsub("\\r"; "")
             | gsub("\n"; "\\n");
           {script: (
             ":foreach id in=[/file/find where name=" + $name + "] do={/file/remove $id}; "
             + "/file/add name=" + $name + " type=file; "
             + "/file/set [/file/find where name=" + $name + "] contents=\"" + ($contents | routeros_escape) + "\""
           )}')"
        response="$(curl "$${curl_options[@]}" --data "$payload" "$routeros_url/execute")"
        if jq -e '(.error // 0) != 0 or ((.ret // "") | test("error|failure"; "i"))' <<<"$response" >/dev/null; then
          echo "RouterOS temporary certificate file write failed." >&2
          exit 1
        fi
      }

      # RouterOS rejects the multi-certificate ACME issuer bundle when it is
      # sent through the REST file-create endpoint. The first certificate is
      # the leaf's immediate issuer and is the only intermediate required in
      # the server chain; clients validate the remaining chain to their roots.
      issuer_pem="$ROUTEROS_ISSUER_PEM"
      if [[ "$issuer_pem" != *"-----BEGIN CERTIFICATE-----"* || "$issuer_pem" != *"-----END CERTIFICATE-----"* ]]; then
        echo "ACME issuer PEM did not contain a certificate." >&2
        exit 1
      fi
      issuer_pem="$${issuer_pem%%-----END CERTIFICATE-----*}-----END CERTIFICATE-----"
      write_file "$ROUTEROS_ISSUER_FILE_NAME" "$issuer_pem"
      write_file "$ROUTEROS_LEAF_FILE_NAME" "$ROUTEROS_LEAF_PEM"
      write_file "$ROUTEROS_KEY_FILE_NAME" "$ROUTEROS_PRIVATE_KEY_PEM"

      run_routeros_script() {
        local script="$1"
        local payload
        local response
        payload="$(jq -cn --arg script "$script" '{script: $script}')"
        response="$(curl "$${curl_options[@]}" --data "$payload" "$routeros_url/execute")"
        if jq -e '(.error // 0) != 0 or ((.ret // "") | test("error|failure"; "i"))' <<<"$response" >/dev/null; then
          echo "RouterOS certificate installation script failed." >&2
          exit 1
        fi
      }

      remove_certificate() {
        local certificate_name="$1"
        local script
        script="$(jq -nr --arg name "$certificate_name" '":foreach id in=[/certificate/find where name=" + $name + "] do={/certificate/remove $id}"')"
        run_routeros_script "$script"
      }

      remove_file() {
        local file_name="$1"
        local script
        script="$(jq -nr --arg name "$file_name" '":foreach id in=[/file/find where name=" + $name + "] do={/file/remove $id}"')"
        run_routeros_script "$script"
      }

      import_certificate() {
        local file_name="$1"
        local certificate_name="$2"
        local trusted="$3"
        local payload
        local response
        payload="$(jq -cn \
          --arg file_name "$file_name" \
          --arg certificate_name "$certificate_name" \
          --arg trusted "$trusted" \
          '{name: $certificate_name, "file-name": $file_name} + (if $trusted == "yes" then {trusted: "yes"} else {} end)')"
        response="$(curl "$${curl_options[@]}" --request POST --data "$payload" "$routeros_url/certificate/import")"
        if jq -e '(.error // 0) != 0 or ((.ret // "") | test("error|failure"; "i"))' <<<"$response" >/dev/null; then
          echo "RouterOS certificate import failed." >&2
          exit 1
        fi
      }

      remove_certificate "$ROUTEROS_CERTIFICATE_NAME"
      remove_certificate "$ROUTEROS_ISSUER_CERTIFICATE_NAME"
      import_certificate "$ROUTEROS_ISSUER_FILE_NAME" "$ROUTEROS_ISSUER_CERTIFICATE_NAME" yes
      import_certificate "$ROUTEROS_LEAF_FILE_NAME" "$ROUTEROS_CERTIFICATE_NAME" yes
      import_certificate "$ROUTEROS_KEY_FILE_NAME" "$ROUTEROS_CERTIFICATE_NAME" no
      remove_file "$ROUTEROS_ISSUER_FILE_NAME"
      remove_file "$ROUTEROS_LEAF_FILE_NAME"
      remove_file "$ROUTEROS_KEY_FILE_NAME"
    EOT

    environment = {
      # Keep credentials in the process environment, never in the command,
      # plan artifact, OpenTofu output, or GitHub Actions log text.
      ROUTEROS_USERNAME                = var.mikrotik_username
      ROUTEROS_PASSWORD                = var.mikrotik_password
      ROUTEROS_INSECURE                = tostring(var.mikrotik_insecure)
      ROUTEROS_CERTIFICATE_NAME        = local.gateway_certificate_name
      ROUTEROS_ISSUER_CERTIFICATE_NAME = local.gateway_issuer_certificate_name
      ROUTEROS_LEAF_FILE_NAME          = local.gateway_leaf_file_name
      ROUTEROS_ISSUER_FILE_NAME        = local.gateway_issuer_file_name
      ROUTEROS_KEY_FILE_NAME           = local.gateway_key_file_name
      ROUTEROS_LEAF_PEM                = acme_certificate.gateway.certificate_pem
      ROUTEROS_ISSUER_PEM              = acme_certificate.gateway.issuer_pem
      ROUTEROS_PRIVATE_KEY_PEM         = acme_certificate.gateway.private_key_pem
    }
  }
}

# RouterOS can retain duplicate `www-ssl` service rows, and the provider does
# not own the built-in service safely. Reconcile the addressed listener on
# every certificate workflow run so service drift is repaired even when ACME
# has not issued a new leaf. `timestamp()` intentionally makes this a live
# check rather than a one-time state transition.
resource "terraform_data" "reconcile_gateway_certificate_service" {
  input            = local.gateway_certificate_name
  triggers_replace = [timestamp()]
  depends_on       = [terraform_data.install_gateway_certificate]

  provisioner "local-exec" {
    # Keep the request construction fail-closed and prevent accidental word
    # splitting when the workflow invokes this on the Linux self-hosted runner.
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      set -euo pipefail
      routeros_url="${trimsuffix(var.mikrotik_hosturl, "/")}/rest"
      curl_options=(--fail --silent --show-error --user "$ROUTEROS_USERNAME:$ROUTEROS_PASSWORD" --header "content-type: application/json")
      if [ "$ROUTEROS_INSECURE" = "true" ]; then
        curl_options+=(--insecure)
      fi

      # RouterOS service IDs are unstable, so discover the one listener with
      # the inventory-verified internal address immediately before updating it.
      services="$(curl "$${curl_options[@]}" "$routeros_url/ip/service")"
      service_id="$(jq -er '[.[] | select(.name == "www-ssl" and ((.address // "") != ""))] | if length == 1 then .[0][".id"] else error("expected one addressed www-ssl service") end' <<<"$services")"
      certificates="$(curl "$${curl_options[@]}" "$routeros_url/certificate")"
      certificate_name="$(jq -er --arg preferred_name "$ROUTEROS_CERTIFICATE_NAME" '
        def is_true: . == true or . == "true";
        [ .[]
          | select(
              .["common-name"] == "gw.bohdal.name"
              and .["private-key"] == "true"
              and ((.expired // false) | is_true | not)
              and ((.invalid // false) | is_true | not)
            )
        ] as $certificates
        | [ $certificates[] | select(.name == $preferred_name) ] as $preferred
        | if ($preferred | length) > 0 then $preferred[-1].name
          elif ($certificates | length) > 0 then ($certificates | sort_by(.["invalid-after"] // "") | .[-1].name)
          else error("no unexpired gateway certificate with private key")
          end
      ' <<<"$certificates")"
      service_payload="$(jq -cn \
        --arg id "$service_id" \
        --arg certificate "$certificate_name" \
        '{".id": $id, certificate: $certificate}')"
      # RouterOS may reset the HTTPS listener immediately after accepting this
      # action. Retry the idempotent update so a transient reset is not
      # mistaken for a failed configuration change.
      service_response=""
      for attempt in {1..10}; do
        if service_response="$(curl "$${curl_options[@]}" --request POST --data "$service_payload" "$routeros_url/ip/service/set")"; then
          break
        fi
        if [ "$attempt" -eq 10 ]; then
          echo "RouterOS HTTPS service update request failed after retries." >&2
          exit 1
        fi
        sleep 1
      done
      # Successful RouterOS action calls can return an array. Only inspect the
      # object-shaped error response here; read-back below verifies the actual
      # service state for both response shapes.
      if jq -e 'type == "object" and ((.error // 0) != 0)' <<<"$service_response" >/dev/null; then
        echo "RouterOS HTTPS service update failed." >&2
        exit 1
      fi

      # The listener restarts while applying the certificate. Poll the
      # read-back endpoint until RouterOS accepts TLS requests again.
      updated_certificate=""
      for attempt in {1..10}; do
        if updated_certificate="$(curl "$${curl_options[@]}" "$routeros_url/ip/service" | jq -er --arg id "$service_id" '.[] | select(.[".id"] == $id) | .certificate')"; then
          break
        fi
        if [ "$attempt" -eq 10 ]; then
          echo "RouterOS HTTPS service read-back failed after retries." >&2
          exit 1
        fi
        sleep 1
      done
      if [[ "$updated_certificate" != "$certificate_name" ]]; then
        echo "RouterOS HTTPS service read-back did not select the unexpired certificate." >&2
        exit 1
      fi
    EOT

    environment = {
      # Keep credentials in the process environment, never in the command or
      # OpenTofu output. The certificate payload is not needed for this check.
      ROUTEROS_USERNAME         = var.mikrotik_username
      ROUTEROS_PASSWORD         = var.mikrotik_password
      ROUTEROS_INSECURE         = tostring(var.mikrotik_insecure)
      ROUTEROS_CERTIFICATE_NAME = local.gateway_certificate_name
    }
  }
}
