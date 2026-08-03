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

      upload_file() {
        local file_name="$1"
        local file_contents="$2"
        local payload
        payload="$(jq -cn --arg name "$file_name" --arg contents "$file_contents" '{name: $name, contents: $contents}')"
        # RouterOS REST creates file resources with PUT, matching the provider
        # transport rather than curl's default POST for --data requests.
        curl "$${curl_options[@]}" --request PUT --data "$payload" "$routeros_url/file" >/dev/null
      }

      upload_file "$ROUTEROS_ISSUER_FILE_NAME" "$ROUTEROS_ISSUER_PEM"
      upload_file "$ROUTEROS_LEAF_FILE_NAME" "$ROUTEROS_LEAF_PEM"
      upload_file "$ROUTEROS_KEY_FILE_NAME" "$ROUTEROS_PRIVATE_KEY_PEM"

      payload="$(jq -cn \
        --arg leaf_name "$ROUTEROS_CERTIFICATE_NAME" \
        --arg issuer_name "$ROUTEROS_ISSUER_CERTIFICATE_NAME" \
        --arg leaf_file "$ROUTEROS_LEAF_FILE_NAME" \
        --arg issuer_file "$ROUTEROS_ISSUER_FILE_NAME" \
        --arg key_file "$ROUTEROS_KEY_FILE_NAME" \
        '{script: (
          ":foreach id in=[/certificate/find where name=\\\"" + $leaf_name + "\\\"] do={/certificate/remove $id}; "
          + ":foreach id in=[/certificate/find where name=\\\"" + $issuer_name + "\\\"] do={/certificate/remove $id}; "
          + "/certificate/import file-name=" + $issuer_file + " name=" + $issuer_name + " trusted=yes; "
          + "/certificate/import file-name=" + $leaf_file + " name=" + $leaf_name + " trusted=yes; "
          + "/certificate/import file-name=" + $key_file + " name=" + $leaf_name + "; "
          + ":foreach id in=[/file/find where name=\\\"" + $issuer_file + "\\\"] do={/file/remove $id}; "
          + ":foreach id in=[/file/find where name=\\\"" + $leaf_file + "\\\"] do={/file/remove $id}; "
          + ":foreach id in=[/file/find where name=\\\"" + $key_file + "\\\"] do={/file/remove $id}"
        )}')"
      response="$(curl "$${curl_options[@]}" --data "$payload" "$routeros_url/execute")"
      if jq -e '(.error // 0) != 0 or ((.ret // "") | test("error|failure"; "i"))' <<<"$response" >/dev/null; then
        echo "RouterOS certificate installation script failed." >&2
        exit 1
      fi

      # RouterOS service IDs are unstable, so discover the one listener with
      # the inventory-verified internal address immediately before updating it.
      services="$(curl "$${curl_options[@]}" "$routeros_url/ip/service")"
      service_id="$(jq -er '[.[] | select(.name == "www-ssl" and ((.address // "") != ""))] | if length == 1 then .[0][".id"] else error("expected one addressed www-ssl service") end' <<<"$services")"
      certificates="$(curl "$${curl_options[@]}" "$routeros_url/certificate")"
      certificate_name="$(jq -er '[.[] | select(.["common-name"] == "gw.bohdal.name" and .["private-key"] == "true")] | if length > 0 then .[-1].name else error("no gateway certificate with private key") end' <<<"$certificates")"
      service_payload="$(jq -cn \
        --arg id "$service_id" \
        --arg certificate "$certificate_name" \
        '{".id": $id, certificate: $certificate}')"
      service_response="$(curl "$${curl_options[@]}" --request POST --data "$service_payload" "$routeros_url/ip/service/set")"
      if jq -e '(.error // 0) != 0' <<<"$service_response" >/dev/null; then
        echo "RouterOS HTTPS service update failed." >&2
        exit 1
      fi
      updated_certificate="$(curl "$${curl_options[@]}" "$routeros_url/ip/service" | jq -er --arg id "$service_id" '.[] | select(.[".id"] == $id) | .certificate')"
      if [[ "$updated_certificate" != "$certificate_name" ]]; then
        echo "RouterOS HTTPS service read-back did not select the imported certificate." >&2
        exit 1
      fi
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
