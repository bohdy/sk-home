-- The candidate location table is swapped with the active copy only after
-- both the IPv4 and IPv6 block files have imported successfully.
CREATE TABLE IF NOT EXISTS flows.geoip_locations_candidate (
    geoname_id UInt32,
    locale_code LowCardinality(String),
    continent_code LowCardinality(String),
    continent_name String,
    country_iso_code LowCardinality(String),
    country_name String,
    subdivision_1_iso_code LowCardinality(String),
    subdivision_1_name String,
    subdivision_2_iso_code LowCardinality(String),
    subdivision_2_name String,
    city_name String,
    metro_code String,
    time_zone String,
    is_in_european_union Nullable(UInt8)
) ENGINE = MergeTree()
ORDER BY geoname_id;
