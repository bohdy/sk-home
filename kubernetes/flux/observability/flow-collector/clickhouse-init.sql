-- Repository-owned ClickHouse schema for goflow2 flow records. Committed DDL
-- applies before any writer starts; the table and its 30-day TTL are defined
-- here rather than being created ad hoc by an exporter or sink.
CREATE DATABASE IF NOT EXISTS flows;

-- The column set mirrors the goflow2 v2.2.6 JSON field names that MikroTik
-- IPFIX populates in practice. The Vector sink runs with skip_unknown_fields,
-- so extra goflow2 fields are ignored server-side instead of breaking inserts.
-- Numeric columns match the bare numbers the default JSON formatter emits;
-- address and protocol columns match its string renderers.
CREATE TABLE IF NOT EXISTS flows.flow (
    timestamp DateTime64(9),
    type LowCardinality(String),
    time_received_ns UInt64,
    sequence_num UInt64,
    sampling_rate UInt64,
    sampler_address String,
    time_flow_start_ns UInt64,
    time_flow_end_ns UInt64,
    bytes UInt64,
    packets UInt64,
    src_addr String,
    dst_addr String,
    etype LowCardinality(String),
    proto LowCardinality(String),
    src_port UInt16,
    dst_port UInt16,
    in_if UInt32,
    out_if UInt32,
    src_mac String,
    dst_mac String,
    flow_direction UInt8,
    icmp_name LowCardinality(String),
    icmp_type UInt8,
    icmp_code UInt8,
    tcp_flags UInt8,
    csum UInt32,
    src_net String,
    dst_net String,
    next_hop String
) ENGINE = MergeTree()
ORDER BY timestamp
TTL timestamp + INTERVAL 30 DAY DELETE;
