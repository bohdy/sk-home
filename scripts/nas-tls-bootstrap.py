#!/usr/bin/env python3
"""Preflight or create the reviewed NAS DSM credential Secret.

The default mode is read-only.  ``--apply-secret`` creates the Secret only
when it is absent; it never adopts, overwrites, or rotates an existing object.
Bitwarden and Kubernetes output stay in memory and are reduced to fixed
diagnostics before they can cross the process boundary.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Mapping


BITWARDEN_PROJECT_NAME = "sk-home"
BITWARDEN_ITEM_KEY = "NAS_TLS_DSM_AUTH"
SECRET_NAME = "nas-tls-dsm-auth"
NAMESPACE_NAME = "nas-tls"
COMMAND_TIMEOUT_SECONDS = 60
MAX_COMMAND_OUTPUT_BYTES = 2 * 1024 * 1024
MAX_SECRET_VALUE_LENGTH = 4096
MAX_ID_LENGTH = 256
EXPECTED_NAMESPACE_LABELS = {
    "pod-security.kubernetes.io/audit": "restricted",
    "pod-security.kubernetes.io/enforce": "restricted",
    "pod-security.kubernetes.io/warn": "restricted",
}
EXPECTED_SECRET_LABELS = {
    "app.kubernetes.io/component": "certificate-delivery-credentials",
    "app.kubernetes.io/name": "nas-tls-dsm-auth",
}
_SAFE_ID = re.compile(r"[A-Za-z0-9._:-]{1,256}\Z")


class BootstrapError(Exception):
    """Fixed diagnostics prevent subprocess payloads entering operator output."""


def token_value(raw: str | None) -> str:
    """Normalize one complete matching quote pair and reject everything else."""

    if not isinstance(raw, str) or not raw or len(raw) > MAX_SECRET_VALUE_LENGTH:
        raise BootstrapError("Bitwarden token unavailable")
    if raw[0] in "\"'" or raw[-1] in "\"'":
        if len(raw) < 3 or raw[0] != raw[-1] or raw[0] not in "\"'":
            raise BootstrapError("Bitwarden token quoting invalid")
        raw = raw[1:-1]
    if not raw or raw[0] in "\"'" or raw[-1] in "\"'":
        raise BootstrapError("Bitwarden token quoting invalid")
    if any(ord(character) < 0x21 or ord(character) == 0x7F for character in raw):
        raise BootstrapError("Bitwarden token quoting invalid")
    return raw


def _bounded_identifier(value: Any, diagnostic: str) -> str:
    """Accept non-secret IDs without logging or accepting control characters."""

    if not isinstance(value, str) or not _SAFE_ID.fullmatch(value):
        raise BootstrapError(diagnostic)
    return value


def execute(
    argv: list[str],
    *,
    env: Mapping[str, str] | None = None,
    payload: str | None = None,
) -> str:
    """Run one external command with bounded, private stdout and stderr."""

    try:
        result = subprocess.run(
            argv,
            input=payload,
            capture_output=True,
            env=dict(env) if env is not None else None,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
            check=False,
        )
        stdout = result.stdout
        stderr = result.stderr
        if not isinstance(stdout, str) or not isinstance(stderr, str):
            raise BootstrapError("External command returned invalid output")
        if (
            len(stdout.encode("utf-8", "replace")) > MAX_COMMAND_OUTPUT_BYTES
            or len(stderr.encode("utf-8", "replace")) > MAX_COMMAND_OUTPUT_BYTES
        ):
            raise BootstrapError("External command output exceeded bound")
        if result.returncode:
            raise BootstrapError("External command failed; payload suppressed")
        return stdout
    except BootstrapError:
        raise
    except (OSError, subprocess.TimeoutExpired):
        raise BootstrapError("External command unavailable; payload suppressed") from None
    except Exception:
        # A mocked or unexpected subprocess failure must not expose argv,
        # private streams, or a traceback that contains a secret payload.
        raise BootstrapError("External command failed; payload suppressed") from None


def document(raw: str) -> Any:
    """Decode bounded JSON while rejecting NaN, Infinity, and malformed data."""

    if not isinstance(raw, str) or len(raw.encode("utf-8", "replace")) > MAX_COMMAND_OUTPUT_BYTES:
        raise BootstrapError("Invalid private response; payload suppressed")

    def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        """Reject duplicate keys so a hostile response cannot hide its value."""

        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    try:
        return json.loads(
            raw,
            object_pairs_hook=unique_pairs,
            parse_constant=lambda _constant: (_ for _ in ()).throw(
                ValueError("non-standard JSON constant")
            ),
        )
    except (TypeError, ValueError, json.JSONDecodeError):
        raise BootstrapError("Invalid private response; payload suppressed") from None


def unique(rows: Any, field: str, value: str) -> dict[str, Any]:
    """Require exactly one metadata row without including it in diagnostics."""

    if not isinstance(rows, list):
        raise BootstrapError("Bitwarden response shape invalid")
    selected = [row for row in rows if isinstance(row, dict) and row.get(field) == value]
    if len(selected) != 1:
        raise BootstrapError("Bitwarden identity is missing or ambiguous")
    return selected[0]


def expected_secret(username: str, password: str) -> dict[str, Any]:
    """Build the exact Opaque Secret sent only through kubectl stdin."""

    return {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": SECRET_NAME,
            "namespace": NAMESPACE_NAME,
            "labels": dict(EXPECTED_SECRET_LABELS),
        },
        "type": "Opaque",
        "data": {
            "username": base64.b64encode(username.encode("utf-8")).decode("ascii"),
            "password": base64.b64encode(password.encode("utf-8")).decode("ascii"),
        },
    }


def _private_value(value: Any, field: str) -> str:
    """Validate one credential value without retaining a diagnostic copy."""

    if (
        not isinstance(value, str)
        or not value
        or len(value) > MAX_SECRET_VALUE_LENGTH
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    ):
        raise BootstrapError(f"Bitwarden {field} value invalid")
    return value


def read_bitwarden_secret(
    item_id: str,
    *,
    runner: Callable[..., str] = execute,
) -> tuple[str, str]:
    """Read and validate the operator-approved item from the trusted project."""

    item_id = _bounded_identifier(item_id, "Bitwarden item identity invalid")
    raw_token = os.environ.get("BWS_ACCESS_TOKEN")
    token = token_value(raw_token)
    with tempfile.TemporaryDirectory(prefix="nas-tls-bws-") as directory:
        config_path = Path(directory) / "config"
        config_path.write_text(
            "[profiles.default]\n"
            'server_base = "https://api.bitwarden.com"\n'
            'server_api = "https://api.bitwarden.com"\n'
            'server_identity = "https://identity.bitwarden.com"\n'
            'state_opt_out = "true"\n',
            encoding="ascii",
        )
        config_path.chmod(0o600)
        # Only the BWS access token and this non-secret configuration path are
        # allowed to enter the Bitwarden subprocess environment.
        bws_env = {
            key: value for key, value in os.environ.items() if not key.startswith("BWS_")
        }
        bws_env.update({"BWS_ACCESS_TOKEN": token, "BWS_CONFIG_FILE": str(config_path)})
        bws = [
            "bws",
            "--profile",
            "default",
            "--config-file",
            str(config_path),
            "--output",
            "json",
        ]
        projects = document(runner(bws + ["project", "list"], env=bws_env))
        project = unique(projects, "name", BITWARDEN_PROJECT_NAME)
        project_id = _bounded_identifier(
            project.get("id"), "Bitwarden project identity invalid"
        )
        item = document(runner(bws + ["secret", "get", item_id], env=bws_env))
        if not isinstance(item, dict):
            raise BootstrapError("Bitwarden Secret response shape invalid")
        if (
            item.get("id") != item_id
            or item.get("key") != BITWARDEN_ITEM_KEY
            or item.get("projectId") != project_id
        ):
            raise BootstrapError("Bitwarden Secret identity or value invalid")
        value = item.get("value")
        if not isinstance(value, str) or not value or len(value) > MAX_COMMAND_OUTPUT_BYTES:
            raise BootstrapError("Bitwarden Secret identity or value invalid")
        payload = document(value)
        if not isinstance(payload, dict) or set(payload) != {"username", "password"}:
            raise BootstrapError("Bitwarden Secret JSON contract invalid")
        return _private_value(payload.get("username"), "username"), _private_value(
            payload.get("password"), "password"
        )


def verify_namespace(value: Any, namespace_uid: str) -> None:
    """Require the independently supplied UID and expected Pod Security labels."""

    namespace_uid = _bounded_identifier(namespace_uid, "Expected namespace identity invalid")
    if not isinstance(value, dict):
        raise BootstrapError("Expected namespace unavailable")
    metadata = value.get("metadata")
    labels = metadata.get("labels") if isinstance(metadata, dict) else None
    if (
        not isinstance(metadata, dict)
        or metadata.get("name") != NAMESPACE_NAME
        or metadata.get("uid") != namespace_uid
        or not isinstance(labels, dict)
        or any(labels.get(key) != expected for key, expected in EXPECTED_NAMESPACE_LABELS.items())
    ):
        raise BootstrapError("Expected namespace unavailable")


def verify_secret(existing: Any, expected: Mapping[str, Any]) -> None:
    """Reject identity, type, data, label, and ownership drift."""

    if not isinstance(existing, dict):
        raise BootstrapError("Existing Secret differs; refusing rotation or adoption")
    metadata = existing.get("metadata")
    expected_metadata = expected.get("metadata", {})
    owner_references = metadata.get("ownerReferences") if isinstance(metadata, dict) else None
    data = existing.get("data")
    if (
        not isinstance(metadata, dict)
        or metadata.get("name") != SECRET_NAME
        or metadata.get("namespace") != NAMESPACE_NAME
        or metadata.get("labels") != expected_metadata.get("labels")
        or owner_references not in (None, [])
        or existing.get("type") != "Opaque"
        or not isinstance(data, dict)
        or set(data) != {"username", "password"}
        or data != expected.get("data")
        or existing.get("stringData") not in (None, {})
    ):
        raise BootstrapError("Existing Secret differs; refusing rotation or adoption")


def _kubernetes_environment() -> dict[str, str]:
    """Keep every BWS_* setting out of kubectl, including inherited extras."""

    return {key: value for key, value in os.environ.items() if not key.startswith("BWS_")}


def bootstrap(
    kubeconfig: str,
    namespace_uid: str,
    item_id: str,
    *,
    apply: bool = False,
    runner: Callable[..., str] = execute,
) -> str:
    """Verify the target and Secret, creating it only when explicitly allowed."""

    _bounded_identifier(namespace_uid, "Expected namespace identity invalid")
    _bounded_identifier(item_id, "Bitwarden item identity invalid")
    if not isinstance(kubeconfig, str) or not kubeconfig or "\x00" in kubeconfig:
        raise BootstrapError("Kubeconfig path invalid")
    kube_env = _kubernetes_environment()
    kube = ["kubectl", "--kubeconfig", kubeconfig]
    namespace = document(
        runner(kube + ["get", "namespace", NAMESPACE_NAME, "-o", "json"], env=kube_env)
    )
    verify_namespace(namespace, namespace_uid)
    username, password = read_bitwarden_secret(item_id, runner=runner)
    expected = expected_secret(username, password)
    raw = runner(
        kube
        + [
            "-n",
            NAMESPACE_NAME,
            "get",
            "secret",
            SECRET_NAME,
            "--ignore-not-found",
            "-o",
            "json",
        ],
        env=kube_env,
    )
    if raw.strip():
        verify_secret(document(raw), expected)
        return "Existing Secret verified; unchanged"
    if not apply:
        return "Secret absent; preflight passed; no mutation"
    # The API server's create operation is atomic.  A concurrent creator is a
    # hard failure, never an invitation to adopt, overwrite, or rotate it.
    runner(
        kube + ["create", "-f", "-", "-o", "name"],
        env=kube_env,
        payload=json.dumps(expected, separators=(",", ":")),
    )
    stored = document(
        runner(
            kube
            + ["-n", NAMESPACE_NAME, "get", "secret", SECRET_NAME, "-o", "json"],
            env=kube_env,
        )
    )
    verify_secret(stored, expected)
    return "Reviewed application Secret created"


def main(argv: list[str] | None = None) -> int:
    """Expose only non-secret metadata and fixed success/failure messages."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--namespace-uid", required=True)
    parser.add_argument(
        "--bitwarden-item-id",
        "--item-id",
        dest="item_id",
        required=True,
        help="Actual operator-approved Bitwarden item ID; never a credential value.",
    )
    parser.add_argument(
        "--apply-secret",
        action="store_true",
        help="Create the absent Secret only after the approved production gate.",
    )
    args = parser.parse_args(argv)
    try:
        print(
            bootstrap(
                args.kubeconfig,
                args.namespace_uid,
                args.item_id,
                apply=args.apply_secret,
            )
        )
        return 0
    except Exception:
        # Unexpected parser/type/subprocess failures must not leak values or
        # tracebacks into CI logs or Kubernetes workload output.
        print("NAS TLS bootstrap refused; private payloads suppressed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
