#!/bin/sh
# Download the licensed GeoLite2 City CSV files, stage them in ClickHouse, and
# exchange the completed tables before reloading the IP_TRIE dictionary. The
# script intentionally never logs credentials or sends individual flow IPs to
# MaxMind; only the database refresh leaves the cluster.
set -eu

work=/work
clickhouse_url=http://clickhouse.observability.svc.cluster.local:8123
maxmind_secret_dir=/var/run/secrets/maxmind

cleanup() {
    rm -f "${work}/.netrc" "${work}/geoip.zip"
    rm -rf "${work}/unpacked"
}

trap cleanup EXIT
mkdir -p "${work}/unpacked"

account_id="$(tr -d '\r\n' < "${maxmind_secret_dir}/account-id")"
license_key="$(tr -d '\r\n' < "${maxmind_secret_dir}/license-key")"
test -n "${account_id}"
test -n "${license_key}"

# A netrc file keeps the credential out of the curl process arguments and is
# removed before any CSV is imported into ClickHouse.
printf 'machine download.maxmind.com\nlogin %s\npassword %s\n' \
    "${account_id}" "${license_key}" > "${work}/.netrc"
chmod 600 "${work}/.netrc"
curl --config /dev/null \
    --fail \
    --silent \
    --show-error \
    --location \
    --netrc-file "${work}/.netrc" \
    --output "${work}/geoip.zip" \
    'https://download.maxmind.com/geoip/databases/GeoLite2-City-CSV/download?suffix=zip'
rm -f "${work}/.netrc"
unset account_id license_key

unzip -q "${work}/geoip.zip" -d "${work}/unpacked"
blocks_ipv4="$(find "${work}/unpacked" -name 'GeoLite2-City-Blocks-IPv4.csv' -print -quit)"
blocks_ipv6="$(find "${work}/unpacked" -name 'GeoLite2-City-Blocks-IPv6.csv' -print -quit)"
locations="$(find "${work}/unpacked" -name 'GeoLite2-City-Locations-en.csv' -print -quit)"
test -s "${blocks_ipv4}"
test -s "${blocks_ipv6}"
test -s "${locations}"

# Keep SQL in the URL and CSV in the request body so ClickHouse receives the
# MaxMind header-aware files without an intermediate parser or shell loop.
run_sql() {
    # ClickHouse requires a Content-Length header for POST mutations; curl's
    # explicit empty body preserves the URL-encoded query without adding data.
    curl --config /dev/null \
        --fail \
        --silent \
        --show-error \
        --request POST \
        --data-binary '' \
        --url-query "query=$1" \
        "${clickhouse_url}/"
}

insert_csv() {
    table="$1"
    csv_file="$2"
    curl --config /dev/null \
        --fail \
        --silent \
        --show-error \
        --url-query "query=INSERT INTO ${table} FORMAT CSVWithNames" \
        --data-binary "@${csv_file}" \
        "${clickhouse_url}/"
}

# A failed import leaves the active dictionary source untouched. The candidate
# copies are replaced atomically only after all three CSV files are complete.
run_sql 'TRUNCATE TABLE flows.geoip_blocks_candidate'
run_sql 'TRUNCATE TABLE flows.geoip_locations_candidate'
insert_csv flows.geoip_blocks_candidate "${blocks_ipv4}"
insert_csv flows.geoip_blocks_candidate "${blocks_ipv6}"
insert_csv flows.geoip_locations_candidate "${locations}"
run_sql 'EXCHANGE TABLES flows.geoip_blocks_active AND flows.geoip_blocks_candidate'
run_sql 'EXCHANGE TABLES flows.geoip_locations_active AND flows.geoip_locations_candidate'
run_sql 'SYSTEM RELOAD DICTIONARY flows.ip_geo'

printf '%s\n' 'GeoIP database refresh completed.'
