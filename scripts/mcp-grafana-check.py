"""Inspect the built Grafana server through the guarded stdio MCP relay."""

import asyncio

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.shared.exceptions import MCPError


async def main() -> None:
    """Use an offline fixture token; no Grafana API calls are made."""
    parameters = StdioServerParameters(
        command="docker",
        args=[
            "run",
            "--rm",
            "-i",
            "--network=none",
            "--entrypoint=/usr/local/bin/grafana-mcp-guard.py",
            "-e",
            "GRAFANA_URL=https://grafana.example.invalid",
            "-e",
            "GRAFANA_SERVICE_ACCOUNT_TOKEN=offline-test-only",
            "-e",
            "MCP_GRAFANA_METRICS_DATASOURCE_UID=VictoriaMetrics",
            "-e",
            "MCP_GRAFANA_LOGS_DATASOURCE_UID=VictoriaLogs",
            "sk-home-mcp-grafana:validation",
            # The official binary remains the child and receives the exact
            # release arguments; the guard owns the policy boundary.
            "--",
            "/usr/local/bin/mcp-grafana",
            "--transport=stdio",
            "--enabled-tools=search,prometheus,loki,alerting,dashboard,folder,navigation",
            "--disable-write",
            "--disable-datasource",
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
        assert len(tools) == 23, "Pinned Grafana tool surface changed"
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
        for name, arguments in (
            (
                "query_prometheus",
                {
                    "datasourceUid": "FlowClickHouseIaC",
                    "expr": "up",
                    "endTime": "now",
                },
            ),
            (
                "query_loki_logs",
                {"datasourceUid": "VictoriaMetrics", "logql": "*"},
            ),
        ):
            try:
                await client.call_tool(name, arguments)
            except MCPError as exc:
                assert str(exc) == "request rejected by policy", (
                    f"{name} was not rejected by the guard"
                )
            else:
                raise AssertionError(f"{name} crossed the datasource policy")
    print("Grafana MCP: guarded initialize/list-tools passed; 23 read-only tools")


if __name__ == "__main__":
    asyncio.run(main())
