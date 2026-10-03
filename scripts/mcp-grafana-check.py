"""Inspect the built Grafana server through real stdio MCP initialization."""

import asyncio

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main() -> None:
    """Use an offline fixture token; no Grafana API calls are made."""
    parameters = StdioServerParameters(
        command="docker",
        args=[
            "run",
            "--rm",
            "-i",
            "--network=none",
            "--entrypoint=/usr/local/bin/mcp-grafana",
            "-e",
            "GRAFANA_URL=https://grafana.example.invalid",
            "-e",
            "GRAFANA_SERVICE_ACCOUNT_TOKEN=offline-test-only",
            "sk-home-mcp-grafana:validation",
            "--transport=stdio",
            "--enabled-tools=search,datasource,prometheus,loki,alerting,dashboard,folder,navigation",
            "--disable-write",
            "--disable-api",
            "--disable-sql",
            "--disable-admin",
            "--disable-proxied",
            "--disable-runpanelquery",
            "--usage-stats=disabled",
            "--log-level=error",
            "--max-loki-log-limit=100",
        ],
    )
    async with (
        stdio_client(parameters) as (reader, writer),
        ClientSession(reader, writer) as client,
    ):
        await client.initialize()
        tools = (await client.list_tools()).tools
        assert len(tools) == 26, "Pinned Grafana tool surface changed"
        assert all(
            tool.annotations and tool.annotations.read_only_hint for tool in tools
        )
        names = {tool.name for tool in tools}
        assert {
            "query_prometheus",
            "query_loki_logs",
            "get_dashboard_by_uid",
            "alerting_rules_read",
        } <= names
        assert not any(
            "sql" in name or "proxied" in name or "runpanel" in name for name in names
        )
        routing = next(tool for tool in tools if tool.name == "alerting_manage_routing")
        enums = routing.input_schema["properties"]["operation"]["enum"]
        assert all(operation.startswith("get_") for operation in enums), (
            "Routing mutation is exposed"
        )
    print(
        "Grafana MCP: initialized; 26 read-only tools; routing operations are read-only"
    )


if __name__ == "__main__":
    asyncio.run(main())
