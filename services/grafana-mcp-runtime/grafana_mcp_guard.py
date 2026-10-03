#!/usr/local/bin/python3
"""Fail-closed JSONL guard for the official Grafana MCP stdio server.

The upstream release remains responsible for Grafana protocol behavior.  This
small standard-library relay only admits the pinned read-only tool catalog and
the two datasource UIDs provisioned by this repository, then forwards parsed
messages using bounded JSONL frames.
"""

from __future__ import annotations

import argparse
import json
import os
import selectors
import signal
import subprocess
import sys
import threading
from collections.abc import Iterable
from typing import Any

METRICS_UID = "VictoriaMetrics"
LOGS_UID = "VictoriaLogs"

# This is the exact read-only catalog verified from Grafana MCP 2.0.0.  A
# changed or expanded upstream catalog must be reviewed before this relay can
# be used with it.
EXPECTED_TOOLS = frozenset(
    {
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
    }
)

PROMETHEUS_TOOLS = frozenset(
    {
        "list_prometheus_label_names",
        "list_prometheus_label_values",
        "list_prometheus_metric_metadata",
        "list_prometheus_metric_names",
        "query_prometheus",
        "query_prometheus_histogram",
    }
)
LOKI_TOOLS = frozenset(
    {
        "list_loki_label_names",
        "list_loki_label_values",
        "query_loki_logs",
        "query_loki_patterns",
        "query_loki_stats",
    }
)

# MCP stdio is newline-delimited JSON.  Keep both directions bounded so a
# malformed peer cannot make the relay retain an unbounded partial frame.
MAX_INPUT_FRAME_BYTES = 256 * 1024
MAX_OUTPUT_FRAME_BYTES = 4 * 1024 * 1024
MAX_JSON_DEPTH = 32
MAX_CONTAINER_ITEMS = 512
MAX_PENDING_CATALOGS = 16

SAFE_CHILD_ENV = frozenset(
    {
        "GRAFANA_URL",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN",
        "DO_NOT_TRACK",
        "PATH",
        "HOME",
        "LANG",
        "LC_ALL",
        "TZ",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
        "NO_COLOR",
    }
)

CLIENT_METHODS = frozenset(
    {
        "initialize",
        "notifications/cancelled",
        "notifications/initialized",
        "ping",
        "tools/call",
        "tools/list",
    }
)
SERVER_NOTIFICATIONS = frozenset(
    {
        "notifications/message",
        "notifications/progress",
        "notifications/resources/list_changed",
        "notifications/tools/list_changed",
    }
)


class GuardError(ValueError):
    """A protocol or policy violation that must never echo caller input."""


class DuplicateMemberError(GuardError):
    """The JSON object contained duplicate member names."""


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Reject duplicate JSON object names before Python overwrites a value."""

    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateMemberError("duplicate object member")
        result[key] = value
    return result


def _parse_json(frame: bytes, *, limit: int) -> Any:
    """Parse one bounded UTF-8 JSON frame with strict JSON semantics."""

    if len(frame) > limit:
        raise GuardError("frame exceeds policy limit")
    try:
        text = frame.decode("utf-8")
        value = json.loads(
            text,
            object_pairs_hook=_object_pairs,
            parse_constant=lambda _value: _raise_constant(),
        )
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        RecursionError,
        GuardError,
    ) as exc:
        raise GuardError("invalid JSON frame") from exc
    _check_shape(value)
    return value


def _raise_constant() -> Any:
    """Make NaN and Infinity fail the strict JSON parser."""

    raise GuardError("non-standard JSON number")


def _check_shape(value: Any, depth: int = 0) -> None:
    """Bound recursive JSON containers before policy logic walks them."""

    if depth > MAX_JSON_DEPTH:
        raise GuardError("JSON nesting exceeds policy limit")
    if isinstance(value, dict):
        if len(value) > MAX_CONTAINER_ITEMS:
            raise GuardError("JSON object exceeds policy limit")
        for key, child in value.items():
            if not isinstance(key, str) or "\x00" in key:
                raise GuardError("invalid JSON object member")
            _check_shape(child, depth + 1)
    elif isinstance(value, list):
        if len(value) > MAX_CONTAINER_ITEMS:
            raise GuardError("JSON array exceeds policy limit")
        for child in value:
            _check_shape(child, depth + 1)
    elif isinstance(value, (str, int, float, bool)) or value is None:
        return
    else:  # pragma: no cover - json.loads does not produce other types.
        raise GuardError("unsupported JSON value")


def _canonical_key(key: str) -> str:
    """Normalize casing and separators for alias detection only."""

    return "".join(char for char in key.casefold() if char.isascii() and char.isalnum())


def _walk_datasource_members(
    value: Any, path: tuple[str, ...] = ()
) -> list[tuple[tuple[str, ...], str, Any]]:
    """Find every datasource binding, including nested and aliased members."""

    bindings: list[tuple[tuple[str, ...], str, Any]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = _canonical_key(key)
            if "%" in key:
                # Encoded names are not part of any accepted schema.  Record
                # them so the caller fails closed even when decoding is partial.
                bindings.append((path, key, child))
            elif normalized.startswith("datasource") or normalized in {
                "dsuid",
                "dsid",
                "dsname",
                "dstype",
            }:
                bindings.append((path, key, child))
            bindings.extend(_walk_datasource_members(child, path + (key,)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            bindings.extend(_walk_datasource_members(child, path + (str(index),)))
    return bindings


def _single_direct_binding(
    arguments: dict[str, Any],
    *,
    expected_uid: str,
    tool_name: str,
    wire_key: str = "datasourceUid",
) -> None:
    """Require one exact top-level UID for a backend query tool."""

    bindings = _walk_datasource_members(arguments)
    if len(bindings) != 1:
        raise GuardError("datasource binding is missing or ambiguous")
    path, key, value = bindings[0]
    if path or key != wire_key or value != expected_uid:
        raise GuardError(f"datasource policy rejected for {tool_name}")


def _optional_alerting_binding(
    arguments: dict[str, Any], *, approved_uids: set[str]
) -> None:
    """Allow only the official optional alerting datasource member."""

    bindings = _walk_datasource_members(arguments)
    if not bindings:
        return
    if len(bindings) != 1:
        raise GuardError("datasource binding is missing or ambiguous")
    path, key, value = bindings[0]
    if path or key != "datasource_uid" or value not in approved_uids:
        raise GuardError("datasource policy rejected")


def _validate_tool_arguments(
    name: str, arguments: Any, *, metrics_uid: str, logs_uid: str
) -> None:
    """Apply the narrow policy for every fixed tool before forwarding it."""

    if not isinstance(arguments, dict):
        raise GuardError("tool arguments must be an object")
    _check_shape(arguments)

    if name in PROMETHEUS_TOOLS:
        _single_direct_binding(arguments, expected_uid=metrics_uid, tool_name=name)
        return
    if name in LOKI_TOOLS:
        _single_direct_binding(arguments, expected_uid=logs_uid, tool_name=name)
        return
    if name == "analyze_loki_labels":
        _single_direct_binding(arguments, expected_uid=logs_uid, tool_name=name)
        return
    if name in {"alerting_manage_routing", "alerting_rules_read"}:
        _optional_alerting_binding(
            arguments,
            approved_uids={metrics_uid, logs_uid},
        )
        return
    if name == "generate_deeplink":
        bindings = _walk_datasource_members(arguments)
        if bindings:
            if len(bindings) != 1:
                raise GuardError("datasource binding is missing or ambiguous")
            path, key, value = bindings[0]
            if path or key != "datasourceUid" or value not in {metrics_uid, logs_uid}:
                raise GuardError("datasource policy rejected")
        if arguments.get("resourceType") == "explore" and not bindings:
            raise GuardError("explore links require an approved datasource UID")
        return
    # Metadata and dashboard reads are allowed, but no unrecognized datasource
    # binding may be smuggled through their free-form nested objects.
    if _walk_datasource_members(arguments):
        raise GuardError("unrecognized datasource binding")


def _validate_tool_catalog(result: Any) -> None:
    """Verify the official binary still exposes exactly the reviewed surface."""

    if not isinstance(result, dict) or not isinstance(result.get("tools"), list):
        raise GuardError("invalid tool catalog")
    tools = result["tools"]
    names: list[str] = []
    for tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str):
            raise GuardError("invalid tool catalog entry")
        name = tool["name"]
        names.append(name)
        annotations = tool.get("annotations")
        if (
            not isinstance(annotations, dict)
            or annotations.get("readOnlyHint") is not True
        ):
            raise GuardError("tool catalog is not read-only")
        if annotations.get("destructiveHint") is True:
            raise GuardError("tool catalog contains a destructive tool")
        schema = tool.get("inputSchema")
        if not isinstance(schema, dict):
            raise GuardError("tool catalog entry has no schema")
        if name in PROMETHEUS_TOOLS | LOKI_TOOLS | {"analyze_loki_labels"}:
            props = schema.get("properties")
            if not isinstance(props, dict) or "datasourceUid" not in props:
                raise GuardError("backend tool lacks its direct UID schema")
    if len(names) != len(set(names)) or set(names) != EXPECTED_TOOLS:
        raise GuardError("tool catalog changed")


def _valid_id(value: Any) -> bool:
    """Accept only JSON-RPC request identifiers that can be tracked safely."""

    return isinstance(value, (str, int)) and not isinstance(value, bool)


def _id_key(value: Any) -> tuple[type[Any], Any]:
    """Separate integer and string IDs even when their values look alike."""

    return (type(value), value)


def _error_message(identifier: Any, code: int, message: str) -> dict[str, Any]:
    """Create a stable error without reflecting params, tool names, or args."""

    return {
        "jsonrpc": "2.0",
        "id": identifier,
        "error": {"code": code, "message": message},
    }


def _child_environment() -> dict[str, str]:
    """Pass only Grafana runtime settings and harmless process settings."""

    return {key: value for key, value in os.environ.items() if key in SAFE_CHILD_ENV}


class Guard:
    """Single-threaded selector relay with an explicit serialized writer."""

    def __init__(self, command: list[str], *, metrics_uid: str, logs_uid: str) -> None:
        self.command = command
        self.metrics_uid = metrics_uid
        self.logs_uid = logs_uid
        self.child: subprocess.Popen[bytes] | None = None
        self.stop_requested = False
        self.pending_catalog_ids: set[tuple[type[Any], Any]] = set()
        self.output_lock = threading.Lock()

    def run(self) -> int:
        """Relay until either stdio endpoint closes, then reap the child."""

        try:
            self.child = subprocess.Popen(
                self.command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                env=_child_environment(),
                start_new_session=True,
            )
        except (OSError, ValueError):
            return 1
        assert self.child.stdin is not None and self.child.stdout is not None
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin.buffer, selectors.EVENT_READ, "client")
        selector.register(self.child.stdout, selectors.EVENT_READ, "child")
        input_buffer = bytearray()
        child_buffer = bytearray()
        old_handlers = self._install_signal_handlers()
        try:
            while not self.stop_requested:
                try:
                    events = selector.select(timeout=0.5)
                except OSError:
                    break
                if self.child.poll() is not None and not any(
                    key.data == "child" for key, _mask in events
                ):
                    break
                for key, _mask in events:
                    if key.data == "client":
                        if not self._read_client(key.fileobj, input_buffer):
                            self.stop_requested = True
                            break
                    else:
                        if not self._read_child(key.fileobj, child_buffer):
                            self.stop_requested = True
                            break
        finally:
            selector.close()
            self._restore_signal_handlers(old_handlers)
            self._stop_child()
        return 0

    def _install_signal_handlers(self) -> dict[int, Any]:
        """Make SIGTERM and SIGINT stop the child process group promptly."""

        previous: dict[int, Any] = {}

        def stop(_signum: int, _frame: Any) -> None:
            self.stop_requested = True
            if self.child is not None and self.child.poll() is None:
                try:
                    os.killpg(self.child.pid, signal.SIGTERM)
                except OSError:
                    pass

        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, stop)
        return previous

    @staticmethod
    def _restore_signal_handlers(previous: dict[int, Any]) -> None:
        """Restore the caller's signal policy after child cleanup."""

        for signum, handler in previous.items():
            signal.signal(signum, handler)

    def _read_client(self, stream: Any, buffer: bytearray) -> bool:
        """Read and process bounded newline-delimited client frames."""

        try:
            chunk = os.read(stream.fileno(), 65536)
        except OSError:
            return False
        if not chunk:
            return False
        buffer.extend(chunk)
        while True:
            newline = buffer.find(b"\n")
            if newline < 0:
                if len(buffer) > MAX_INPUT_FRAME_BYTES:
                    buffer.clear()
                    self._send(_error_message(None, -32600, "invalid request"))
                    # Do not interpret the remaining suffix of an oversized
                    # unterminated frame as a separate request. Close safely.
                    return False
                return True
            frame = bytes(buffer[:newline]).rstrip(b"\r")
            del buffer[: newline + 1]
            if len(frame) > MAX_INPUT_FRAME_BYTES or not frame.strip():
                self._send(_error_message(None, -32600, "invalid request"))
                continue
            parsed_message: Any = None
            try:
                parsed_message = _parse_json(frame, limit=MAX_INPUT_FRAME_BYTES)
            except GuardError:
                self._send(_error_message(None, -32600, "invalid request"))
                continue
            try:
                self._handle_client_message(parsed_message)
            except GuardError as exc:
                del exc
                identifier = None
                if isinstance(parsed_message, dict):
                    candidate = parsed_message.get("id")
                    if _valid_id(candidate):
                        identifier = candidate
                if identifier is not None or not (
                    isinstance(parsed_message, dict) and "id" not in parsed_message
                ):
                    self._send(
                        _error_message(
                            identifier,
                            -32602,
                            "request rejected by policy",
                        )
                    )
        return True

    def _read_child(self, stream: Any, buffer: bytearray) -> bool:
        """Parse child output before forwarding it to the client."""

        try:
            chunk = os.read(stream.fileno(), 65536)
        except OSError:
            return False
        if not chunk:
            return False
        buffer.extend(chunk)
        if len(buffer) > MAX_OUTPUT_FRAME_BYTES and b"\n" not in buffer:
            self._send(
                _error_message(None, -32603, "MCP child output exceeded policy limit")
            )
            return False
        while True:
            newline = buffer.find(b"\n")
            if newline < 0:
                return True
            frame = bytes(buffer[:newline]).rstrip(b"\r")
            del buffer[: newline + 1]
            if len(frame) > MAX_OUTPUT_FRAME_BYTES or not frame.strip():
                self._send(_error_message(None, -32603, "invalid MCP child output"))
                return False
            try:
                message = _parse_json(frame, limit=MAX_OUTPUT_FRAME_BYTES)
                self._handle_child_message(message)
            except GuardError:
                self._send(
                    _error_message(None, -32603, "MCP child output rejected by policy")
                )
                return False

    def _handle_client_message(self, message: Any) -> None:
        """Validate one client request and forward only a rebuilt message."""

        if isinstance(message, list) or not isinstance(message, dict):
            raise GuardError("batch and scalar requests are not accepted")
        if message.get("jsonrpc") != "2.0" or not isinstance(
            message.get("method"), str
        ):
            raise GuardError("invalid JSON-RPC request")
        method = message["method"]
        if method not in CLIENT_METHODS:
            if "id" in message and _valid_id(message["id"]):
                self._send(_error_message(message["id"], -32601, "method not found"))
            return
        has_id = "id" in message
        identifier = message.get("id")
        if has_id and not _valid_id(identifier):
            raise GuardError("invalid request identifier")
        if method.startswith("notifications/") and has_id:
            raise GuardError("notification must not have an identifier")
        params = message.get("params", {})
        if not isinstance(params, dict):
            raise GuardError("request parameters must be an object")
        _check_shape(params)
        if method == "tools/call":
            if not has_id:
                # Notifications are valid JSON-RPC, but they still go through
                # the same policy gate before the child sees them.
                identifier = None
            self._validate_call(params)
        elif _walk_datasource_members(params):
            raise GuardError("unrecognized datasource binding")
        if method == "tools/list":
            if not has_id:
                raise GuardError("tools/list requires an identifier")
            key = _id_key(identifier)
            if key in self.pending_catalog_ids:
                raise GuardError("duplicate outstanding request identifier")
            if len(self.pending_catalog_ids) >= MAX_PENDING_CATALOGS:
                raise GuardError("too many outstanding catalog requests")
            self.pending_catalog_ids.add(key)
        rebuilt: dict[str, Any] = {"jsonrpc": "2.0", "method": method, "params": params}
        if has_id:
            rebuilt["id"] = identifier
        self._write_child(rebuilt)

    def _validate_call(self, params: dict[str, Any]) -> None:
        """Validate tool name, argument shape, and every nested binding alias."""

        if set(params) - {"name", "arguments", "_meta"}:
            raise GuardError("unsupported tool call parameters")
        if "_meta" in params:
            metadata = params["_meta"]
            if (
                not isinstance(metadata, dict)
                or set(metadata) - {"progressToken"}
                or "_meta" in metadata
                or _walk_datasource_members(metadata)
            ):
                raise GuardError("unsupported tool call metadata")
            _check_shape(metadata)
            if "progressToken" in metadata and not isinstance(
                metadata["progressToken"], (str, int)
            ):
                raise GuardError("invalid progress token")
        name = params.get("name")
        if not isinstance(name, str) or name not in EXPECTED_TOOLS:
            raise GuardError("unknown tool")
        arguments = params.get("arguments", {})
        _validate_tool_arguments(
            name,
            arguments,
            metrics_uid=self.metrics_uid,
            logs_uid=self.logs_uid,
        )

    def _handle_child_message(self, message: Any) -> None:
        """Validate child responses/notifications and forward canonical JSON."""

        if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
            raise GuardError("invalid child message")
        if isinstance(message.get("method"), str):
            if "id" in message or message["method"] not in SERVER_NOTIFICATIONS:
                raise GuardError("unsupported child request")
            if message["method"] == "notifications/tools/list_changed":
                # The fixed catalog cannot safely accept a dynamic new tool.
                raise GuardError("child tool catalog changed")
            self._send(message)
            return
        if "id" not in message or not _valid_id(message["id"]):
            raise GuardError("invalid child response")
        identifier = message["id"]
        key = _id_key(identifier)
        if "result" in message and "error" in message:
            raise GuardError("child response contains both result and error")
        if "result" in message and key in self.pending_catalog_ids:
            self.pending_catalog_ids.remove(key)
            _validate_tool_catalog(message["result"])
        elif "error" in message:
            # Failed discovery completes its outstanding request too; callers
            # can retry without accumulating stale IDs against the bound.
            self.pending_catalog_ids.discard(key)
            # Child errors can contain backend URLs or reflected expressions;
            # keep only a stable protocol error while preserving the request ID.
            sanitized = _error_message(identifier, -32603, "MCP child request failed")
            self._send(sanitized)
            return
        elif "result" not in message:
            raise GuardError("invalid child response")
        self._send(message)

    def _write_child(self, message: dict[str, Any]) -> None:
        """Serialize a parsed message and write it under the relay lock."""

        if self.child is None or self.child.stdin is None:
            raise GuardError("MCP child is unavailable")
        try:
            payload = (
                json.dumps(
                    message, ensure_ascii=False, separators=(",", ":"), allow_nan=False
                ).encode("utf-8")
                + b"\n"
            )
            if len(payload) > MAX_INPUT_FRAME_BYTES:
                raise GuardError("request exceeds policy limit")
            with self.output_lock:
                self.child.stdin.write(payload)
                self.child.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise GuardError("MCP child is unavailable") from exc

    def _send(self, message: dict[str, Any]) -> None:
        """Serialize one safe response without exposing malformed input."""

        try:
            payload = (
                json.dumps(
                    message, ensure_ascii=False, separators=(",", ":"), allow_nan=False
                ).encode("utf-8")
                + b"\n"
            )
            if len(payload) > MAX_OUTPUT_FRAME_BYTES:
                raise GuardError("response exceeds policy limit")
            with self.output_lock:
                sys.stdout.buffer.write(payload)
                sys.stdout.buffer.flush()
        except (BrokenPipeError, OSError):
            self.stop_requested = True

    def _stop_child(self) -> None:
        """Close stdin, terminate the process group, and reap without hanging."""

        if self.child is None:
            return
        try:
            if self.child.stdin is not None:
                self.child.stdin.close()
        except OSError:
            pass
        if self.child.poll() is None:
            try:
                os.killpg(self.child.pid, signal.SIGTERM)
            except OSError:
                try:
                    self.child.terminate()
                except OSError:
                    pass
            try:
                self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.child.pid, signal.SIGKILL)
                except OSError:
                    try:
                        self.child.kill()
                    except OSError:
                        pass
                try:
                    self.child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
        try:
            if self.child.stdout is not None:
                self.child.stdout.close()
        except OSError:
            pass


def _configured_uid(name: str, default: str) -> str:
    """Read a non-secret deployment setting and fail closed on drift."""

    value = os.environ.get(name, default)
    if value != default:
        raise GuardError("datasource UID configuration is not approved")
    return value


def _arguments(argv: Iterable[str]) -> tuple[str, str, list[str]]:
    """Split guard options from the unchanged official child command."""

    values = list(argv)
    try:
        separator = values.index("--")
    except ValueError as exc:
        raise GuardError("child command separator is required") from exc
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(
        "--metrics-datasource-uid",
        default=os.environ.get("MCP_GRAFANA_METRICS_DATASOURCE_UID", METRICS_UID),
    )
    parser.add_argument(
        "--logs-datasource-uid",
        default=os.environ.get("MCP_GRAFANA_LOGS_DATASOURCE_UID", LOGS_UID),
    )
    options, unknown = parser.parse_known_args(values[:separator])
    if unknown or not values[separator + 1 :]:
        raise GuardError("invalid guard options")
    if (
        options.metrics_datasource_uid != METRICS_UID
        or options.logs_datasource_uid != LOGS_UID
    ):
        raise GuardError("datasource UID configuration is not approved")
    return (
        options.metrics_datasource_uid,
        options.logs_datasource_uid,
        values[separator + 1 :],
    )


def main(argv: list[str] | None = None) -> int:
    """Start the guarded official binary and return after bounded cleanup."""

    try:
        metrics_uid, logs_uid, command = _arguments(
            sys.argv[1:] if argv is None else argv
        )
        metrics_uid = _configured_uid("MCP_GRAFANA_METRICS_DATASOURCE_UID", metrics_uid)
        logs_uid = _configured_uid("MCP_GRAFANA_LOGS_DATASOURCE_UID", logs_uid)
    except (GuardError, OSError, ValueError, RecursionError):
        return 2
    try:
        return Guard(command, metrics_uid=metrics_uid, logs_uid=logs_uid).run()
    except Exception:  # noqa: BLE001 - fail closed without exposing child details.
        # Do not let an unexpected child/protocol failure emit a traceback that
        # could contain environment or backend details.
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
