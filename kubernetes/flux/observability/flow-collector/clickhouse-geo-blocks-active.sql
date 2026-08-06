-- Keep the active MaxMind network ranges separate from the candidate copy so
-- the refresh job can build a complete replacement before swapping it in.
CREATE TABLE IF NOT EXISTS flows.geoip_blocks_active (
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
