-- Keep tunable map policy values in ClickHouse so dashboard queries do not
-- duplicate thresholds that operators may adjust after observing the data.
CREATE TABLE IF NOT EXISTS flows.geo_settings (
    setting LowCardinality(String),
    value UInt32
) ENGINE = MergeTree()
ORDER BY setting;
