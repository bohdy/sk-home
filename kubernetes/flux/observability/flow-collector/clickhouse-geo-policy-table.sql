-- Countries at or above the configured area threshold receive city-level
-- markers when the GeoLite2 record has a sufficiently small accuracy radius.
CREATE TABLE IF NOT EXISTS flows.geo_country_policy (
    country_iso_code String,
    area_km2 UInt32,
    city_enabled UInt8
) ENGINE = MergeTree()
ORDER BY country_iso_code;
