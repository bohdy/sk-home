-- The candidate table is truncated and repopulated by each successful GeoIP
-- refresh, then exchanged with the active table atomically.
CREATE TABLE IF NOT EXISTS flows.geoip_blocks_candidate (
    network String,
    geoname_id Nullable(UInt32),
    registered_country_geoname_id Nullable(UInt32),
    represented_country_geoname_id Nullable(UInt32),
    is_anonymous_proxy Nullable(UInt8),
    is_satellite_provider Nullable(UInt8),
    postal_code String,
    latitude Nullable(Float64),
    longitude Nullable(Float64),
    accuracy_radius Nullable(UInt16)
) ENGINE = MergeTree()
ORDER BY network;
