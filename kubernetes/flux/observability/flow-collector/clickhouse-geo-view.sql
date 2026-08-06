-- Join the active MaxMind ranges to English locations and the reviewed country
-- policy. The IP_TRIE dictionary reads this view instead of raw CSV tables.
CREATE OR REPLACE VIEW flows.geoip_source AS
SELECT
    blocks.network AS network,
    if(
        city.country_iso_code != '',
        city.country_iso_code,
        if(
            registered.country_iso_code != '',
            registered.country_iso_code,
            if(represented.country_iso_code != '', represented.country_iso_code, '')
        )
    ) AS country_code,
    if(
        city.country_name != '',
        city.country_name,
        if(
            registered.country_name != '',
            registered.country_name,
            if(represented.country_name != '', represented.country_name, '')
        )
    ) AS country_name,
    if(city.city_name != '', city.city_name, '') AS city_name,
    ifNull(blocks.latitude, 0.0) AS latitude,
    ifNull(blocks.longitude, 0.0) AS longitude,
    ifNull(blocks.accuracy_radius, 0) AS accuracy_radius,
    if(policy.country_iso_code != '', policy.city_enabled, 0) AS city_enabled
FROM flows.geoip_blocks_active AS blocks
LEFT JOIN flows.geoip_locations_active AS city
    ON city.geoname_id = blocks.geoname_id AND city.locale_code = 'en'
LEFT JOIN flows.geoip_locations_active AS registered
    ON registered.geoname_id = blocks.registered_country_geoname_id
    AND registered.locale_code = 'en'
LEFT JOIN flows.geoip_locations_active AS represented
    ON represented.geoname_id = blocks.represented_country_geoname_id
    AND represented.locale_code = 'en'
LEFT JOIN flows.geo_country_policy AS policy
    ON policy.country_iso_code = if(
        city.country_iso_code != '',
        city.country_iso_code,
        if(
            registered.country_iso_code != '',
            registered.country_iso_code,
            represented.country_iso_code
        )
    );
