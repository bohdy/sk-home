-- A city point is shown only when its database-reported uncertainty is within
-- this limit; larger or missing radii fall back to a country marker.
INSERT INTO flows.geo_settings (setting, value) VALUES
    ('city_accuracy_radius_km', 100);
