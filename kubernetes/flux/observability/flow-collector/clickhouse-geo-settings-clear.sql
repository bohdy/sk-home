-- Make the committed threshold seed safe across Job retries and schema
-- reapplication; the table contains desired configuration, not user data.
TRUNCATE TABLE flows.geo_settings;
