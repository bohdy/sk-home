"""Offline tests for the unauthenticated NAS path preflight."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import ssl
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
SCRIPT_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/nas_tls_path_preflight.py"
JOB_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/path-preflight-job.yaml"
KUSTOMIZATION_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/kustomization.yaml"
POLICY_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/issue/network-policy.yaml"
OLD_JOB_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/job.yaml"


SPEC = importlib.util.spec_from_file_location("nas_tls_path_preflight", SCRIPT_PATH)
assert SPEC and SPEC.loader
PREFLIGHT = importlib.util.module_from_spec(SPEC)
sys.modules["nas_tls_path_preflight"] = PREFLIGHT
SPEC.loader.exec_module(PREFLIGHT)


class FakeRawSocket:
    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FakeTlsSocket:
    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FakeTlsContext:
    def __init__(self, socket: FakeTlsSocket) -> None:
        self.socket = socket
        self.calls: list[tuple[object, dict[str, object]]] = []

    def wrap_socket(self, raw_socket: object, **kwargs: object) -> FakeTlsSocket:
        self.calls.append((raw_socket, kwargs))
        return self.socket


class PathPreflightTests(unittest.TestCase):
    def test_fixed_endpoint_uses_one_bounded_canonical_tls_handshake(self) -> None:
        raw_socket = FakeRawSocket()
        tls_socket = FakeTlsSocket()
        context = FakeTlsContext(tls_socket)
        calls: list[tuple[tuple[str, int], float]] = []

        def connect(address: tuple[str, int], *, timeout: float) -> FakeRawSocket:
            calls.append((address, timeout))
            return raw_socket

        with patch.object(PREFLIGHT.socket, "create_connection", side_effect=connect):
            with patch.object(PREFLIGHT, "_tls_context", return_value=context):
                self.assertTrue(PREFLIGHT.run_preflight())
        self.assertEqual(calls, [(("10.1.100.10", 5001), 10.0)])
        self.assertEqual(len(context.calls), 1)
        self.assertIs(context.calls[0][0], raw_socket)
        self.assertEqual(
            context.calls[0][1],
            {
                "server_hostname": "nas.bohdy.sk",
                "do_handshake_on_connect": True,
            },
        )
        self.assertTrue(tls_socket.closed)

    def test_transport_context_requires_tls12_but_ignores_old_leaf(self) -> None:
        context = PREFLIGHT._tls_context()
        self.assertEqual(context.minimum_version, ssl.TLSVersion.TLSv1_2)
        self.assertFalse(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_NONE)

    def test_bounded_failure_closes_socket_without_exception_details(self) -> None:
        raw_socket = FakeRawSocket()

        class BrokenContext:
            def wrap_socket(self, _raw_socket: object, **_kwargs: object) -> object:
                raise RuntimeError("private transport detail")

        with patch.object(PREFLIGHT.socket, "create_connection", return_value=raw_socket):
            with patch.object(PREFLIGHT, "_tls_context", return_value=BrokenContext()):
                self.assertFalse(PREFLIGHT.run_preflight())
        self.assertTrue(raw_socket.closed)
        output = io.StringIO()
        with patch.object(PREFLIGHT, "run_preflight", return_value=False):
            with contextlib.redirect_stdout(output):
                self.assertEqual(PREFLIGHT.main(), 1)
        self.assertEqual(output.getvalue(), "nas-tls path preflight: failed\n")
        self.assertNotIn("private transport detail", output.getvalue())

    def test_script_has_no_http_api_or_runtime_override(self) -> None:
        source = SCRIPT_PATH.read_text(encoding="utf-8")
        for forbidden in (
            "http.client",
            "urllib",
            "requests",
            "argparse",
            "os.environ",
            "os.getenv",
            "sys.argv",
            "urlopen",
            "request(",
        ):
            self.assertNotIn(forbidden, source)
        self.assertIn("10.1.100.10", source)
        self.assertIn("nas.bohdy.sk", source)
        self.assertIn("TLSv1_2", source)

    def test_job_has_no_auth_source_or_kubernetes_credential_mount(self) -> None:
        job = JOB_PATH.read_text(encoding="utf-8")
        self.assertIn("app.kubernetes.io/name: nas-tls-delivery", job)
        self.assertIn("automountServiceAccountToken: false", job)
        self.assertIn("nas-tls-path-preflight-v1", job)
        self.assertIn("backoffLimit: 0", job)
        self.assertIn("activeDeadlineSeconds: 300", job)
        self.assertIn("restartPolicy: Never", job)
        for forbidden in (
            "secretName:",
            "source-certificate",
            "dsm-auth",
            "serviceAccountName:",
            "/source",
            "/auth",
            "/etc/nas-tls",
            "nas_tls_bootstrap.py",
        ):
            self.assertNotIn(forbidden, job)

    def test_rendered_job_selects_existing_policy_and_old_inspect_stays_inactive(self) -> None:
        result = subprocess.run(
            ["kubectl", "kustomize", str(ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap")],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        jobs = [
            document
            for document in result.stdout.split("\n---\n")
            if "kind: Job\n" in document
        ]
        self.assertEqual(len(jobs), 1)
        self.assertIn("name: nas-tls-path-preflight-v1", jobs[0])
        self.assertIn("app.kubernetes.io/name: nas-tls-delivery", jobs[0])
        self.assertIn("name: nas-tls-path-preflight", jobs[0])
        self.assertIn("ip: 10.1.100.10", jobs[0])
        self.assertIn("- nas.bohdy.sk", jobs[0])
        self.assertIn("- nas.bohdal.name", jobs[0])
        self.assertIn(
            "image: docker.io/library/python:3.14.8-slim-bookworm@sha256:",
            jobs[0],
        )
        self.assertNotIn("nas-tls-bootstrap-inspect-v1", result.stdout)
        self.assertNotIn("nas_tls_bootstrap.py", result.stdout)

        policy = POLICY_PATH.read_text(encoding="utf-8")
        selector = policy.split("endpointSelector:", 1)[1].split("ingress:", 1)[0]
        self.assertIn("app.kubernetes.io/name: nas-tls-delivery", selector)
        kustomization = KUSTOMIZATION_PATH.read_text(encoding="utf-8")
        self.assertIn("path-preflight-job.yaml", kustomization)
        self.assertIn("nas_tls_path_preflight.py", kustomization)
        self.assertNotIn("  - job.yaml", kustomization)
        self.assertIn("name: nas-tls-bootstrap-inspect-v1", OLD_JOB_PATH.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
