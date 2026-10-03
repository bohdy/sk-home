"""Offline subprocess tests for the Grafana MCP stdio policy relay."""

from __future__ import annotations

import errno
import json
import os
import selectors
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

GUARD = Path(__file__).parents[1] / "grafana_mcp_guard.py"
MAX_INPUT_FRAME_BYTES = 256 * 1024

TOOLS = [
    "alerting_manage_routing",
    "alerting_rules_read",
    "alerting_silences_read",
    "analyze_loki_labels",
    "generate_deeplink",
    "get_dashboard_by_uid",
    "get_dashboard_panel_queries",
    "get_dashboard_property",
    "get_dashboard_summary",
    "list_dashboard_versions",
    "list_loki_label_names",
    "list_loki_label_values",
    "list_prometheus_label_names",
    "list_prometheus_label_values",
    "list_prometheus_metric_metadata",
    "list_prometheus_metric_names",
    "query_loki_logs",
    "query_loki_patterns",
    "query_loki_stats",
    "query_prometheus",
    "query_prometheus_histogram",
    "search_dashboards",
    "search_folders",
]
PROMETHEUS_TOOLS = {
    "list_prometheus_label_names",
    "list_prometheus_label_values",
    "list_prometheus_metric_metadata",
    "list_prometheus_metric_names",
    "query_prometheus",
    "query_prometheus_histogram",
}
LOKI_TOOLS = {
    "list_loki_label_names",
    "list_loki_label_values",
    "query_loki_logs",
    "query_loki_patterns",
    "query_loki_stats",
}


FIXTURE_SOURCE = textwrap.dedent(
    """
    import json
    import os
    from pathlib import Path
    import sys
    import time

    log_path, pid_path, env_path = map(Path, sys.argv[1:4])
    pid_path.write_text(str(os.getpid()), encoding="utf-8")
    env_path.write_text(json.dumps(dict(os.environ)), encoding="utf-8")
    sys.stderr.write("fixture-child-secret-should-not-escape\\n")
    sys.stderr.flush()
    names = %r
    prom = %r
    loki = %r

    def schema(name):
        properties = {}
        if name in prom or name in loki or name == "analyze_loki_labels":
            properties["datasourceUid"] = {"type": "string"}
        return {"type": "object", "properties": properties}

    catalog = [
        {
            "name": name,
            "description": "fixture",
            "inputSchema": schema(name),
            "annotations": {
                "readOnlyHint": True,
                "destructiveHint": False,
            },
        }
        for name in names
    ]

    def emit(message):
        sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\\n")
        sys.stdout.flush()

    with log_path.open("a", encoding="utf-8") as log:
        for raw in sys.stdin:
            message = json.loads(raw)
            log.write(json.dumps(message, sort_keys=True) + "\\n")
            log.flush()
            method = message.get("method")
            if method == "initialize":
                emit({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                        "protocolVersion": "2025-06-18",
                        "capabilities": {"tools": {"listChanged": False}},
                        "serverInfo": {"name": "fixture", "version": "1"},
                    },
                })
            elif method == "tools/list":
                if message.get("params", {}).get("cursor") == "fixture-error":
                    emit({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32603, "message": "fixture-child-secret"}})
                else:
                    emit({"jsonrpc": "2.0", "id": message["id"], "result": {"tools": catalog}})
            elif method == "tools/call":
                emit({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {"content": [{"type": "text", "text": "fixture-ok"}]},
                })

    # Keep an EOF test's child alive until the guard has demonstrated bounded
    # process-group cleanup rather than relying on normal stdin shutdown.
    time.sleep(60)
    """
)


class GuardSubprocessTests(unittest.TestCase):
    """Exercise the guard with a deterministic backend that records calls."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="grafana-guard-")
        root = Path(self.temp_dir.name)
        self.fixture = root / "fixture.py"
        self.log_path = root / "calls.jsonl"
        self.pid_path = root / "child.pid"
        self.env_path = root / "child-env.json"
        self.fixture.write_text(
            FIXTURE_SOURCE
            % (
                TOOLS,
                sorted(PROMETHEUS_TOOLS),
                sorted(LOKI_TOOLS),
            ),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env.update(
            {
                "GRAFANA_URL": "https://grafana.example.invalid",
                "GRAFANA_SERVICE_ACCOUNT_TOKEN": "grafana-test-token",
                "MCP_GRAFANA_METRICS_DATASOURCE_UID": "VictoriaMetrics",
                "MCP_GRAFANA_LOGS_DATASOURCE_UID": "VictoriaLogs",
                "CONTROL_PLANE_API_KEY": "control-plane-secret",
                "BWS_ACCESS_TOKEN": "bitwarden-secret",
                "OPENAI_API_KEY": "openai-secret",
            }
        )
        self.process = subprocess.Popen(
            [
                sys.executable,
                str(GUARD),
                "--",
                sys.executable,
                str(self.fixture),
                str(self.log_path),
                str(self.pid_path),
                str(self.env_path),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        self.assertIsNotNone(self.process.stdin)
        self.assertIsNotNone(self.process.stdout)
        self._send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "guard-test", "version": "1"},
                },
            }
        )
        self.assertEqual(self._read()["id"], 1)
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self._send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        catalog = self._read()
        self.assertEqual(catalog["id"], 2)
        self.assertEqual(len(catalog["result"]["tools"]), 23)

    def tearDown(self) -> None:
        if self.process.poll() is None:
            assert self.process.stdin is not None
            self.process.stdin.close()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        if self.process.stderr is not None:
            self.assertNotIn(b"fixture-child-secret", self.process.stderr.read())
        for stream in (
            self.process.stdin,
            self.process.stdout,
            self.process.stderr,
        ):
            if stream is not None and not stream.closed:
                stream.close()
        self.temp_dir.cleanup()

    def _send(self, message: dict[str, object]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(
            json.dumps(message, separators=(",", ":")).encode() + b"\n"
        )
        self.process.stdin.flush()

    def _send_raw(self, payload: bytes) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(payload)
        self.process.stdin.flush()

    def _read(self) -> dict[str, object]:
        assert self.process.stdout is not None
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            self.assertTrue(selector.select(timeout=3), "guard did not answer in time")
            line = self.process.stdout.readline()
        finally:
            selector.close()
        self.assertTrue(line, "guard closed stdout unexpectedly")
        value = json.loads(line)
        self.assertIsInstance(value, dict)
        return value

    def _calls(self) -> list[dict[str, object]]:
        if not self.log_path.exists():
            return []
        return [
            json.loads(line)
            for line in self.log_path.read_text(encoding="utf-8").splitlines()
        ]

    def _assert_rejected(self, message: dict[str, object]) -> None:
        self._send(message)
        response = self._read()
        self.assertEqual(response["id"], message.get("id"))
        self.assertEqual(response["error"]["message"], "request rejected by policy")
        self.assertNotIn("arguments", response["error"])
        self.assertFalse(
            any(call.get("method") == "tools/call" for call in self._calls())
        )

    def test_allowed_prometheus_uid_reaches_fixture(self) -> None:
        self._send(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "query_prometheus",
                    "arguments": {
                        "datasourceUid": "VictoriaMetrics",
                        "expr": "up",
                        "endTime": "now",
                    },
                },
            }
        )
        response = self._read()
        self.assertEqual(response["id"], 3)
        self.assertIn("result", response)
        self.assertTrue(
            any(call.get("method") == "tools/call" for call in self._calls())
        )

    def test_standard_meta_and_cached_call_work_before_tools_list(self) -> None:
        root = Path(self.temp_dir.name)
        cached_log = root / "cached-calls.jsonl"
        cached_pid = root / "cached.pid"
        cached_env = root / "cached-env.json"
        env = os.environ.copy()
        env.update(
            {
                "GRAFANA_URL": "https://grafana.example.invalid",
                "GRAFANA_SERVICE_ACCOUNT_TOKEN": "grafana-test-token",
                "MCP_GRAFANA_METRICS_DATASOURCE_UID": "VictoriaMetrics",
                "MCP_GRAFANA_LOGS_DATASOURCE_UID": "VictoriaLogs",
            }
        )
        process = subprocess.Popen(
            [
                sys.executable,
                str(GUARD),
                "--",
                sys.executable,
                str(self.fixture),
                str(cached_log),
                str(cached_pid),
                str(cached_env),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        try:
            assert process.stdin is not None and process.stdout is not None
            process.stdin.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {
                            "name": "query_prometheus",
                            "_meta": {"progressToken": "cached-3"},
                            "arguments": {
                                "datasourceUid": "VictoriaMetrics",
                                "expr": "up",
                                "endTime": "now",
                            },
                        },
                    },
                    separators=(",", ":"),
                ).encode()
                + b"\n"
            )
            process.stdin.flush()
            self.assertEqual(json.loads(process.stdout.readline())["id"], 3)
            recorded = [
                json.loads(line)
                for line in cached_log.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(
                recorded[0]["params"]["_meta"]["progressToken"], "cached-3"
            )
        finally:
            if process.poll() is None:
                assert process.stdin is not None
                process.stdin.close()
                process.wait(timeout=3)
            for stream in (process.stdout, process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()

    def test_loki_and_prometheus_uids_are_category_specific(self) -> None:
        self._assert_rejected(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "query_loki_logs",
                    "arguments": {"datasourceUid": "VictoriaMetrics", "logql": "*"},
                },
            }
        )

    def test_flow_missing_nested_conflicting_and_encoded_uids_are_rejected(
        self,
    ) -> None:
        cases = [
            {"datasourceUid": "FlowClickHouseIaC", "expr": "up", "endTime": "now"},
            {"expr": "up", "endTime": "now"},
            {
                "datasourceUid": "VictoriaMetrics",
                "nested": {"datasourceUID": "VictoriaMetrics"},
                "expr": "up",
                "endTime": "now",
            },
            {"data%73ourceUid": "VictoriaMetrics", "expr": "up", "endTime": "now"},
        ]
        for index, arguments in enumerate(cases, start=3):
            with self.subTest(arguments=arguments):
                self._assert_rejected(
                    {
                        "jsonrpc": "2.0",
                        "id": index,
                        "method": "tools/call",
                        "params": {
                            "name": "query_prometheus",
                            "arguments": arguments,
                        },
                    }
                )

    def test_duplicate_json_members_are_rejected_before_fixture(self) -> None:
        self._send_raw(
            b'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_prometheus","arguments":{"datasourceUid":"VictoriaMetrics","datasourceUid":"FlowClickHouseIaC"}}}\n'
        )
        response = self._read()
        self.assertIsNone(response["id"])
        self.assertEqual(response["error"]["message"], "invalid request")
        self.assertFalse(
            any(call.get("method") == "tools/call" for call in self._calls())
        )

    def test_unknown_tool_and_ambiguous_health_are_rejected(self) -> None:
        self._assert_rejected(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "query_prometheus_new",
                    "arguments": {},
                },
            }
        )
        self._assert_rejected(
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {
                    "name": "check_datasources_health",
                    "arguments": {},
                },
            }
        )

    def test_generic_datasource_tools_are_not_advertised_or_forwarded(self) -> None:
        # Generic metadata and health tools are disabled upstream; cached
        # client calls must still fail before reaching the child.
        for index, name in enumerate(
            ("list_datasources", "get_datasource", "check_datasources_health"), start=5
        ):
            self._assert_rejected(
                {
                    "jsonrpc": "2.0",
                    "id": index,
                    "method": "tools/call",
                    "params": {"name": name, "arguments": {}},
                }
            )

    def test_malformed_batch_and_oversized_frames_are_safe(self) -> None:
        self._send_raw(b"not-json\n")
        malformed = self._read()
        self.assertIsNone(malformed["id"])
        self.assertEqual(malformed["error"]["message"], "invalid request")
        self._send_raw(b"[]\n")
        batch = self._read()
        self.assertIsNone(batch["id"])
        self.assertEqual(batch["error"]["message"], "request rejected by policy")
        self._send_raw(b"x" * (MAX_INPUT_FRAME_BYTES + 1) + b"\n")
        oversized = self._read()
        self.assertIsNone(oversized["id"])
        self.assertEqual(oversized["error"]["message"], "invalid request")

    def test_failed_catalog_requests_release_retry_capacity(self) -> None:
        # More retries than the outstanding-ID bound must remain available
        # when every previous request already completed with a child error.
        for identifier in range(10, 28):
            self._send(
                {
                    "jsonrpc": "2.0",
                    "id": identifier,
                    "method": "tools/list",
                    "params": {"cursor": "fixture-error"},
                }
            )
            self.assertEqual(
                self._read()["error"]["message"], "MCP child request failed"
            )
        self._send({"jsonrpc": "2.0", "id": 28, "method": "tools/list", "params": {}})
        self.assertEqual(len(self._read()["result"]["tools"]), 23)

    def test_oversized_unterminated_frame_closes_without_dispatch(self) -> None:
        # A suffix must never become a fresh frame after clearing a full buffer.
        self._send_raw(b"x" * (MAX_INPUT_FRAME_BYTES + 1))
        self.assertEqual(self._read()["error"]["message"], "invalid request")
        self.process.wait(timeout=3)
        self.assertFalse(
            any(call.get("method") == "tools/call" for call in self._calls())
        )

    def test_child_environment_is_minimal_and_stderr_is_not_forwarded(self) -> None:
        child_env = json.loads(self.env_path.read_text(encoding="utf-8"))
        self.assertEqual(child_env["GRAFANA_URL"], "https://grafana.example.invalid")
        self.assertEqual(
            child_env["GRAFANA_SERVICE_ACCOUNT_TOKEN"], "grafana-test-token"
        )
        for secret_name in (
            "CONTROL_PLANE_API_KEY",
            "BWS_ACCESS_TOKEN",
            "OPENAI_API_KEY",
        ):
            self.assertNotIn(secret_name, child_env)

    def test_eof_and_sigterm_reap_the_child_process(self) -> None:
        child_pid = int(self.pid_path.read_text(encoding="utf-8"))
        assert self.process.stdin is not None
        self.process.stdin.close()
        self.process.wait(timeout=3)
        self._assert_pid_gone(child_pid)

        replacement = subprocess.Popen(
            [
                sys.executable,
                str(GUARD),
                "--",
                sys.executable,
                str(self.fixture),
                str(self.log_path),
                str(self.pid_path),
                str(self.env_path),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=os.environ
            | {
                "MCP_GRAFANA_METRICS_DATASOURCE_UID": "VictoriaMetrics",
                "MCP_GRAFANA_LOGS_DATASOURCE_UID": "VictoriaLogs",
            },
        )
        for _ in range(20):
            if self.pid_path.exists():
                break
            time.sleep(0.05)
        replacement_child_pid = int(self.pid_path.read_text(encoding="utf-8"))
        replacement.send_signal(signal.SIGTERM)
        replacement.wait(timeout=3)
        self._assert_pid_gone(replacement_child_pid)
        for stream in (
            replacement.stdin,
            replacement.stdout,
            replacement.stderr,
        ):
            if stream is not None and not stream.closed:
                stream.close()

    @staticmethod
    def _assert_pid_gone(pid: int) -> None:
        for _ in range(20):
            try:
                os.kill(pid, 0)
            except OSError as exc:
                if exc.errno == errno.ESRCH:
                    return
                raise
            time.sleep(0.05)
        raise AssertionError(f"child process {pid} survived guard cleanup")


if __name__ == "__main__":
    unittest.main()
