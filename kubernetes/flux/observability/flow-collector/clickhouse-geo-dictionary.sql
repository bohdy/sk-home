-- IP_TRIE performs longest-prefix matching for both IPv4 and IPv6 flow
-- addresses while keeping the high-volume raw flow table unchanged.
CREATE OR REPLACE DICTIONARY flows.ip_geo (
    network String,
    country_code String,
    country_name String,
    city_name String,
    latitude Float64,
    longitude Float64,
    accuracy_radius UInt16,
    city_enabled UInt8
)
PRIMARY KEY network
SOURCE(CLICKHOUSE(
    HOST '127.0.0.1'
    PORT 9000
    USER 'default'
    TABLE 'geoip_source'
    DB 'flows'
))
LIFETIME(MIN 3600 MAX 7200)
LAYOUT(IP_TRIE);
