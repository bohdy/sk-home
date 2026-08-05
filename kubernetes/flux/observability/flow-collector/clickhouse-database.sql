-- Repository-owned ClickHouse database DDL. Keep this as one statement because
-- the ClickHouse HTTP endpoint rejects multiple statements in one POST request.
CREATE DATABASE IF NOT EXISTS flows;
