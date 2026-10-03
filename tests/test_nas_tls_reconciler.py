"""Offline tests for the NAS TLS reconciler.

The fixture creates a private CA and short-lived leaf with OpenSSL, then uses
loopback TLS and in-memory HTTP responses.  No DSM, kubeconfig, credential, or
network access is required.
"""

from __future__ import annotations

import contextlib
import dataclasses
import hashlib
import http.client
import importlib.util
import io
import json
import os
import ssl
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


MODULE_PATH = (
    Path(__file__).parents[1]
    / "kubernetes"
    / "flux"
    / "infrastructure"
    / "nas-tls"
    / "issue"
    / "nas_tls_reconciler.py"
)
SPEC = importlib.util.spec_from_file_location("nas_tls_reconciler", MODULE_PATH)
assert SPEC and SPEC.loader
RECONCILER = importlib.util.module_from_spec(SPEC)
sys.modules["nas_tls_reconciler"] = RECONCILER
SPEC.loader.exec_module(RECONCILER)


def run_openssl(*args: str) -> None:
    """Run a fixture-only OpenSSL command without exposing command output."""

    subprocess.run(
        ["openssl", *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


class Fixture:
    """Private CA and leaf chain used by every source validation test."""

    def __init__(self, root: Path, *, hostname: str = "nas.bohdal.name", days: int = 30) -> None:
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.source = root / "source"
        self.source.mkdir()
        self.ca_key = root / "ca.key"
        self.ca_cert = root / "ca.pem"
        run_openssl(
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-subj",
            "/CN=NAS test CA",
            "-days",
            "365",
            "-keyout",
            str(self.ca_key),
            "-out",
            str(self.ca_cert),
            "-addext",
            "basicConstraints=critical,CA:TRUE",
            "-addext",
            "keyUsage=critical,keyCertSign,cRLSign",
        )
        self.key = self.source / "tls.key"
        self.cert = self.source / "tls.crt"
        self._issue_leaf(hostname, days)

    def _issue_leaf(self, hostname: str, days: int) -> None:
        csr = self.root / "leaf.csr"
        ext = self.root / "leaf.ext"
        ext.write_text(
            "[v3]\n"
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            f"subjectAltName=DNS:{hostname}\n",
            encoding="ascii",
        )
        run_openssl(
            "req",
            "-new",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-subj",
            f"/CN={hostname}",
            "-keyout",
            str(self.key),
            "-out",
            str(csr),
        )
        leaf = self.root / "leaf.pem"
        run_openssl(
            "x509",
            "-req",
            "-in",
            str(csr),
            "-CA",
            str(self.ca_cert),
            "-CAkey",
            str(self.ca_key),
            "-CAcreateserial",
            "-days",
            str(days),
            "-out",
            str(leaf),
            "-extfile",
            str(ext),
            "-extensions",
            "v3",
        )
        self.cert.write_bytes(leaf.read_bytes() + self.ca_cert.read_bytes())

    def config(self, **overrides: Any) -> Any:
        values = dict(
            hostname="nas.bohdal.name",
            port=5001,
            source_cert=str(self.cert),
            source_key=str(self.key),
            auth_directory=str(self.root / "auth"),
            target_description="nas.bohdal.name cert-manager",
            target_id="stable-id",
            minimum_lifetime_seconds=24 * 60 * 60,
            timeout_seconds=3,
            response_limit_bytes=64 * 1024,
            upload_limit_bytes=512 * 1024,
            retry_count=1,
            retry_delay_seconds=0,
            ca_file=str(self.ca_cert),
        )
        values.update(overrides)
        return RECONCILER.Config(**values)


class FakeResponse:
    def __init__(self, value: bytes, status: int = 200) -> None:
        self.value = value
        self.status = status

    def getheader(self, name: str) -> str | None:
        if name.lower() == "content-length":
            return str(len(self.value))
        return None

    def read(self, _limit: int = -1) -> bytes:
        return self.value


class FakeConnection:
    def __init__(self, response: FakeResponse, recorder: list[dict[str, Any]]) -> None:
        self.response = response
        self.recorder = recorder

    def request(self, method: str, path: str, body: bytes | None, headers: dict[str, str]) -> None:
        self.recorder.append({"method": method, "path": path, "body": body or b"", "headers": headers})

    def getresponse(self) -> FakeResponse:
        return self.response

    def close(self) -> None:
        return None


class QueueClient(RECONCILER.DsmClient):
    """Fake DSM state machine used to exercise reconcile control flow."""

    def __init__(
        self,
        config: Any,
        source_fingerprint: str,
        *,
        mismatch: bool = False,
        mutate_inventory: bool = False,
    ) -> None:
        super().__init__(config, connect_host="127.0.0.1")
        self.source_fingerprint = source_fingerprint
        self.fingerprints = ["old", source_fingerprint] if not mismatch else ["old", "still-old"]
        self.imported = False
        self.logged_out = False
        self.list_calls = 0
        self.default = RECONCILER.TargetSnapshot(
            "default-id", "DSM default", True, ("management",)
        )
        self.target = RECONCILER.TargetSnapshot("stable-id", config.target_description, False, ("dsm",))
        self.other = RECONCILER.TargetSnapshot("other-id", "Other certificate", False, ("other",))
        self.before_certificates = [self.default, self.target, self.other]
        self.after_certificates = list(self.before_certificates)
        if mutate_inventory:
            # The target remains pinned, but an unrelated global binding changes.
            # Reconciliation must fail rather than silently overwrite that drift.
            self.after_certificates[0] = RECONCILER.TargetSnapshot(
                "default-id", "DSM default", True, ("management", "unexpected")
            )

    def served_fingerprint(self) -> str:
        return self.fingerprints.pop(0) if self.fingerprints else "still-old"

    def discover(self) -> Any:
        return RECONCILER.Discovery("auth.cgi", 7)

    def login(self, _discovery: Any, _username: str, _password: str) -> Any:
        return RECONCILER.Session("sid", "token")

    def list_certificates(self, _session: Any) -> list[Any]:
        self.list_calls += 1
        return list(self.before_certificates if self.list_calls == 1 else self.after_certificates)

    def import_certificate(self, _session: Any, _target: Any, _snapshot: Any) -> None:
        self.imported = True

    def logout(self, _discovery: Any, _session: Any) -> None:
        self.logged_out = True


class ReconcilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.fixture = Fixture(self.root)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _auth(self) -> None:
        auth = self.root / "auth"
        auth.mkdir(exist_ok=True)
        (auth / "username").write_text("admin", encoding="ascii")
        (auth / "password").write_text("password", encoding="ascii")

    def test_loopback_fullchain_validation_and_snapshot(self) -> None:
        config = self.fixture.config()
        snapshot = RECONCILER.load_source_snapshot(config)
        self.assertTrue(snapshot.intermediate_pem)
        RECONCILER.validate_source_snapshot(config, snapshot)
        self.assertEqual(snapshot.fingerprint, hashlib.sha256(snapshot.leaf_der).hexdigest())

    def test_secret_projection_rotation_fails_closed(self) -> None:
        mounted = self.root / "mounted"
        old_projection = mounted / "..data-old"
        new_projection = mounted / "..data-new"
        mounted.mkdir()
        old_projection.mkdir()
        new_projection.mkdir()
        for projection in (old_projection, new_projection):
            (projection / "tls.crt").write_bytes(self.fixture.cert.read_bytes())
            (projection / "tls.key").write_bytes(self.fixture.key.read_bytes())
        cert_link = mounted / "tls.crt"
        key_link = mounted / "tls.key"
        cert_link.symlink_to("..data-old/tls.crt")
        key_link.symlink_to("..data-old/tls.key")
        config = self.fixture.config(source_cert=str(cert_link), source_key=str(key_link))
        snapshot = RECONCILER.load_source_snapshot(config)

        for name in ("tls.crt", "tls.key"):
            replacement = mounted / f".{name}.next"
            replacement.symlink_to(f"..data-new/{name}")
            os.replace(replacement, mounted / name)
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "source_changed"):
            snapshot.assert_stable()

    def test_activation_placeholder_fails_before_noop_or_credentials(self) -> None:
        config = self.fixture.config(target_id=RECONCILER.ACTIVATION_PLACEHOLDER)
        client = QueueClient(config, RECONCILER.load_source_snapshot(config).fingerprint)
        client.fingerprints = [client.source_fingerprint]
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "target_id_not_pinned"):
            RECONCILER.reconcile(config, client=client)
        self.assertFalse((self.root / "auth").exists())

    def test_noop_skips_credentials_after_target_pin(self) -> None:
        config = self.fixture.config()
        client = QueueClient(config, RECONCILER.load_source_snapshot(config).fingerprint)
        client.fingerprints = [client.source_fingerprint]
        self.assertEqual(RECONCILER.reconcile(config, client=client), "noop")
        self.assertFalse((self.root / "auth").exists())

    def test_rotation_imports_once_and_logs_out(self) -> None:
        self._auth()
        config = self.fixture.config()
        snapshot = RECONCILER.load_source_snapshot(config)
        client = QueueClient(config, snapshot.fingerprint)
        self.assertEqual(RECONCILER.reconcile(config, client=client), "rotated")
        self.assertTrue(client.imported)
        self.assertTrue(client.logged_out)
        self.assertEqual(client.before_certificates[0], client.after_certificates[0])
        self.assertEqual(client.before_certificates[2], client.after_certificates[2])

    def test_rotation_rejects_unrelated_global_binding_change(self) -> None:
        self._auth()
        config = self.fixture.config()
        snapshot = RECONCILER.load_source_snapshot(config)
        client = QueueClient(config, snapshot.fingerprint, mutate_inventory=True)
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "certificate_inventory_changed"):
            RECONCILER.reconcile(config, client=client)
        self.assertTrue(client.imported)
        self.assertTrue(client.logged_out)

    def test_provider_shaped_bindings_use_owner_service_package_identity(self) -> None:
        first = {
            "service": "shared-label",
            "display_name": "Owner A",
            "owner": "owner-a",
            "isPkg": False,
        }
        second = {
            "service": "shared-label",
            "display_name": "Owner B",
            "owner": "owner-b",
            "isPkg": False,
        }
        reversed_services = RECONCILER._normalize_services([second, first])
        self.assertEqual(
            reversed_services,
            RECONCILER._normalize_services([first, second]),
        )
        certificates = [
            RECONCILER.TargetSnapshot("default", "Default", True, (first,)),
            RECONCILER.TargetSnapshot("target", "Target", False, (second,)),
        ]
        # Different owners may share DSM's service label; both bindings remain
        # part of the global inventory comparison.
        self.assertTrue(RECONCILER._inventory_signature(certificates))
        duplicate = [
            RECONCILER.TargetSnapshot("default", "Default", True, (first,)),
            RECONCILER.TargetSnapshot("target", "Target", False, (dict(first),)),
        ]
        with self.assertRaisesRegex(
            RECONCILER.ReconcileError, "certificate_inventory_ambiguous"
        ):
            RECONCILER._inventory_signature(duplicate)

    def test_multipart_import_preserves_validated_snapshot_and_wire_contract(self) -> None:
        records: list[dict[str, Any]] = []
        config = self.fixture.config()
        snapshot = RECONCILER.load_source_snapshot(config)
        RECONCILER.validate_source_snapshot(config, snapshot)
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(b'{"success":true,"data":{}}'), records
            ),
        )
        default_target = RECONCILER.TargetSnapshot(
            "stable-id", config.target_description, True, ()
        )
        client.import_certificate(
            RECONCILER.Session("SID-secret", "TOKEN-secret"),
            default_target,
            snapshot,
        )
        request = records[0]
        content_type = request["headers"]["Content-Type"]
        boundary = content_type.split("boundary=", 1)[1].encode("ascii")
        parts: dict[str, bytes] = {}
        for chunk in request["body"].split(b"--" + boundary):
            if b"Content-Disposition:" not in chunk:
                continue
            headers, value = chunk.split(b"\r\n\r\n", 1)
            # Remove only the multipart framing CRLF; certificate and key PEM
            # snapshots intentionally retain their own final newline byte.
            self.assertTrue(value.endswith(b"\r\n"))
            value = value[:-2]
            marker = b'name="'
            start = headers.index(marker) + len(marker)
            name = headers[start : headers.index(b'"', start)].decode("ascii")
            parts[name] = value
        self.assertEqual(
            set(parts),
            {"key", "cert", "inter_cert", "id", "desc", "api", "method", "version", "as_default"},
        )
        self.assertEqual(parts["key"], snapshot.key_pem)
        self.assertEqual(parts["cert"], snapshot.leaf_pem)
        self.assertEqual(parts["inter_cert"], snapshot.intermediate_pem)
        self.assertEqual(parts["id"], b"stable-id")
        self.assertEqual(parts["desc"], config.target_description.encode("utf-8"))
        self.assertEqual(parts["api"], b"SYNO.Core.Certificate")
        self.assertEqual(parts["method"], b"import")
        self.assertEqual(parts["version"], b"1")
        self.assertEqual(parts["as_default"], b"true")
        self.assertNotIn(b"SID-secret", request["path"].encode() + request["body"])
        self.assertNotIn(b"TOKEN-secret", request["path"].encode() + request["body"])
        self.assertEqual(request["headers"]["Cookie"], "id=SID-secret")
        self.assertEqual(request["headers"]["X-SYNO-TOKEN"], "TOKEN-secret")

        records.clear()
        non_default_target = dataclasses.replace(default_target, is_default=False)
        client.import_certificate(
            RECONCILER.Session("SID-secret", "TOKEN-secret"),
            non_default_target,
            dataclasses.replace(snapshot, intermediate_pem=b""),
        )
        non_default_body = records[0]["body"]
        self.assertNotIn(b'name="inter_cert"', non_default_body)
        self.assertNotIn(b'name="as_default"', non_default_body)

    def test_valid_source_then_remote_tls_failure_makes_no_auth_or_import_calls(self) -> None:
        config = self.fixture.config()
        snapshot = RECONCILER.load_source_snapshot(config)
        # Prove the mounted source is valid before injecting the independent
        # remote peer failure.
        RECONCILER.validate_source_snapshot(config, snapshot)
        calls = {"discover": 0, "login": 0, "import": 0}

        def failing_socket(_address: tuple[str, int], _timeout: float) -> Any:
            raise ssl.SSLError("hostile remote peer")

        class CountingClient(RECONCILER.DsmClient):
            def discover(self) -> Any:
                calls["discover"] += 1
                raise AssertionError("authentication discovery must not run")

            def login(self, _discovery: Any, _username: str, _password: str) -> Any:
                calls["login"] += 1
                raise AssertionError("login must not run")

            def import_certificate(self, _session: Any, _target: Any, _source: Any) -> None:
                calls["import"] += 1
                raise AssertionError("import must not run")

        client = CountingClient(config, socket_factory=failing_socket)
        with self.assertRaisesRegex(
            RECONCILER.ReconcileError, "dsm_tls_verification_failed"
        ):
            RECONCILER.reconcile(config, client=client)
        self.assertEqual(calls, {"discover": 0, "login": 0, "import": 0})

    def test_hostile_bounds_are_sanitized(self) -> None:
        records: list[dict[str, Any]] = []
        config = self.fixture.config(response_limit_bytes=4096)
        oversized = FakeResponse(b"x" * 4097)
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(oversized, records),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "response_too_large"):
            client.discover()
        hostile_id = "x" * (RECONCILER.MAX_CERTIFICATE_ID_LENGTH + 1)
        response = FakeResponse(
            json.dumps(
                {
                    "success": True,
                    "data": {
                        "certificates": [
                            {
                                "id": hostile_id,
                                "desc": "desc",
                                "is_default": True,
                                "services": [],
                            }
                        ]
                    },
                }
            ).encode()
        )
        bounded_client = RECONCILER.DsmClient(
            self.fixture.config(),
            connection_factory=lambda _config, _context: FakeConnection(response, []),
        )
        with self.assertRaisesRegex(
            RECONCILER.ReconcileError, "certificate_list_schema_invalid"
        ):
            bounded_client.list_certificates(RECONCILER.Session("sid", "token"))

    def test_source_key_mismatch_chain_and_snapshot_change_fail_closed(self) -> None:
        other = Fixture(self.root / "other")
        mismatch_key = self.fixture.source / "mismatch.key"
        mismatch_key.write_bytes(other.key.read_bytes())
        config = self.fixture.config(source_key=str(mismatch_key))
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "source_key_mismatch"):
            RECONCILER.validate_source_snapshot(config, RECONCILER.load_source_snapshot(config))
        bad = self.fixture.cert.read_bytes() + b"hostile trailing data"
        self.fixture.cert.write_bytes(bad)
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "source_chain_invalid"):
            RECONCILER.load_source_snapshot(config=self.fixture.config(source_key=str(self.fixture.key)))

    def test_expired_not_yet_valid_and_wrong_name_dates_are_rejected(self) -> None:
        now = RECONCILER.time.time()
        config = self.fixture.config()
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "expired"):
            RECONCILER._validate_peer_dates(
                {"notBefore": "Jan  1 00:00:00 2020 GMT", "notAfter": "Jan  2 00:00:00 2020 GMT"}, config
            )
        future = RECONCILER.time.strftime("%b %d %H:%M:%S %Y GMT", RECONCILER.time.gmtime(now + 3600))
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "not_yet"):
            RECONCILER._validate_peer_dates(
                {"notBefore": future, "notAfter": "Jan  2 00:00:00 2099 GMT"}, config
            )
        wrong = Fixture(self.root / "wrong", hostname="other.example")
        wrong_config = wrong.config()
        with self.assertRaises(RECONCILER.ReconcileError):
            RECONCILER.validate_source_snapshot(wrong_config, RECONCILER.load_source_snapshot(wrong_config))

    def test_missing_duplicate_and_pinned_target(self) -> None:
        config = self.fixture.config()
        target = RECONCILER.TargetSnapshot("id", config.target_description, False, ())
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "target_missing"):
            RECONCILER._target_for_import(config, [])
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "target_duplicate"):
            RECONCILER._target_for_import(config, [target, target])
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "target_id_mismatch"):
            RECONCILER._target_for_import(config, [target])

    def test_runtime_config_rejects_custom_ca_file(self) -> None:
        config_path = self.root / "config.json"
        config_path.write_text(
            json.dumps(
                {
                    "hostname": "nas.bohdal.name",
                    "port": 5001,
                    "source_cert": str(self.fixture.cert),
                    "source_key": str(self.fixture.key),
                    "auth_directory": str(self.root / "auth"),
                    "target_description": "nas.bohdal.name cert-manager",
                    "target_id": "stable-id",
                    "ca_file": str(self.fixture.ca_cert),
                }
            ),
            encoding="ascii",
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "config_invalid"):
            RECONCILER.Config.from_file(str(config_path))

    def test_discovery_schema_and_api_errors_are_sanitized(self) -> None:
        records: list[dict[str, Any]] = []
        discovery = {
            "success": True,
            "data": {
                "SYNO.API.Auth": {"path": "auth.cgi", "minVersion": 1, "maxVersion": 7},
                "SYNO.Core.Certificate.CRT": {"path": "entry.cgi", "minVersion": 1, "maxVersion": 1},
                "SYNO.Core.Certificate": {"path": "entry.cgi", "minVersion": 1, "maxVersion": 1},
            },
        }
        config = self.fixture.config()
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(json.dumps(discovery).encode()), records
            ),
        )
        result = client.discover()
        self.assertEqual(result.auth_path, "auth.cgi")
        self.assertIn("SYNO.Core.Certificate", records[0]["path"])
        bad = dict(discovery)
        bad["data"] = {**discovery["data"], "SYNO.API.Auth": {"path": "../../evil", "maxVersion": 7}}
        bad_client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(json.dumps(bad).encode()), []
            ),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "discovery_contract_invalid"):
            bad_client.discover()
        error_client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(b'{"success":false,"error":{"code":999,"detail":"TOPSECRET"}}'), []
            ),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "api_error") as error:
            error_client.discover()
        self.assertNotIn("TOPSECRET", str(error.exception))

    def test_session_wire_has_no_secrets_in_url_and_redirect_is_rejected(self) -> None:
        records: list[dict[str, Any]] = []
        response = FakeResponse(
            b'{"success":true,"data":{"certificates":['
            b'{"id":"default-id","desc":"DSM default","is_default":true,"services":[]}'
            b']}}'
        )
        config = self.fixture.config()
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(response, records),
        )
        client.list_certificates(RECONCILER.Session("SID-secret", "TOKEN-secret"))
        request = records[0]
        self.assertNotIn(b"SID-secret", request["path"].encode())
        self.assertNotIn(b"TOKEN-secret", request["path"].encode())
        self.assertNotIn(b"SID-secret", request["body"])
        self.assertNotIn(b"TOKEN-secret", request["body"])
        self.assertEqual(request["headers"]["Cookie"], "id=SID-secret")
        self.assertEqual(request["headers"]["X-SYNO-TOKEN"], "TOKEN-secret")
        redirect_client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(b"Location: https://host/secret", status=302), []
            ),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "redirect_rejected"):
            redirect_client.discover()

    def test_session_separator_is_rejected_before_authenticated_request(self) -> None:
        config = self.fixture.config()
        records: list[dict[str, Any]] = []
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(b'{"success":true,"data":{"certificates":[]}}'), records
            ),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "auth_response_invalid"):
            client.login(
                RECONCILER.Discovery("auth.cgi", 7),
                "user",
                "pass",
            )
        # A malicious server response is supplied by a custom response below;
        # the login path must reject separators before a session is constructed.
        bad = FakeResponse(b'{"success":true,"data":{"sid":"SID;Path=/","synotoken":"token"}}')
        bad_client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(bad, records),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "auth_response_invalid"):
            bad_client.login(RECONCILER.Discovery("auth.cgi", 7), "user", "pass")

    def test_upload_failure_post_import_mismatch_and_hostile_output(self) -> None:
        records: list[dict[str, Any]] = []
        config = self.fixture.config()
        source = RECONCILER.load_source_snapshot(config)
        client = RECONCILER.DsmClient(
            config,
            connection_factory=lambda _config, _context: FakeConnection(
                FakeResponse(b'{"success":false,"error":{"detail":"TOPSECRET"}}'), records
            ),
        )
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "api_error") as error:
            client.import_certificate(
                RECONCILER.Session("sid", "token"),
                RECONCILER.TargetSnapshot("id", "desc", False, ()),
                source,
            )
        self.assertNotIn("TOPSECRET", str(error.exception))
        self._auth()
        mismatch = QueueClient(config, source.fingerprint, mismatch=True)
        with self.assertRaisesRegex(RECONCILER.ReconcileError, "served_certificate_mismatch"):
            RECONCILER.reconcile(config, client=mismatch)

    def test_ready_rule_uses_true_condition_gauge(self) -> None:
        """Model cert-manager's three condition gauges without a live Prometheus."""

        rule = (
            MODULE_PATH.parents[3]
            / "observability"
            / "nas-tls"
            / "vm-rules.yaml"
        ).read_text(encoding="utf-8")
        self.assertIn('condition="True",namespace="nas-tls",name="nas-tls"', rule)
        self.assertIn("kube_cronjob_created", rule)
        self.assertIn("bootstrap Job does not populate this CronJob metric", rule)

        def fires(series: dict[str, float]) -> bool:
            # cert-manager emits one ready gauge per condition.  Only the True
            # series is authoritative; False and Unknown remain zero when the
            # certificate is Ready and must not create a duplicate alert.
            return series.get("True") != 1

        self.assertFalse(fires({"True": 1, "False": 0, "Unknown": 0}))
        self.assertTrue(fires({"True": 0, "False": 1, "Unknown": 0}))
        self.assertTrue(fires({}))

    def test_completed_import_is_not_blindly_retried_by_kubernetes(self) -> None:
        for relative in (
            "infrastructure/nas-tls/delivery/cronjob.yaml",
            "infrastructure/nas-tls/bootstrap/job.yaml",
        ):
            manifest = (
                MODULE_PATH.parents[3] / relative
            ).read_text(encoding="utf-8")
            self.assertIn("backoffLimit: 0", manifest)
            self.assertIn("restartPolicy: Never", manifest)


if __name__ == "__main__":
    unittest.main()
