"""Focused offline tests for the versioned NAS TLS bootstrap Job."""

from __future__ import annotations

import http.server
import importlib.util
import json
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]
RECONCILER_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/issue/nas_tls_reconciler.py"
BOOTSTRAP_PATH = ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/nas_tls_bootstrap.py"


def load_module(name: str, path: Path):
    """Load repository modules without installing a package."""

    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


COMMON = load_module("nas_tls_reconciler", RECONCILER_PATH)
BOOTSTRAP = load_module("nas_tls_bootstrap", BOOTSTRAP_PATH)
SUPPORT = load_module("nas_tls_reconciler_test_support", ROOT / "tests/test_nas_tls_reconciler.py")


class InventoryClient:
    """Credential-free DSM state machine for bootstrap control-flow tests."""

    def __init__(
        self,
        config,
        certificates,
        *,
        fingerprint: str = "old",
        import_error: str | None = None,
        state: dict[str, bool] | None = None,
        mutate_then_error: bool = False,
    ) -> None:
        self.config = config
        self.certificates = list(certificates)
        self.fingerprint = fingerprint
        self.import_error = import_error
        self.state = state if state is not None else {"imported": False}
        self.mutate_then_error = mutate_then_error
        self.import_calls = 0
        self.logout_calls = 0
        self.sealed = False
        self.sessions: list[COMMON.Session] = []

    def discover(self):
        return COMMON.Discovery("auth.cgi", 7)

    def login(self, _discovery, _username: str, _password: str):
        session = COMMON.Session("synthetic-sid", "synthetic-token")
        self.sessions.append(session)
        return session

    def list_certificates(self, _session):
        return list(self.certificates)

    def import_certificate(self, _session, _target, _snapshot) -> None:
        self.import_calls += 1
        if self.mutate_then_error:
            # Model DSM committing the new leaf before returning an ambiguous
            # API error envelope; strict clients share this state below.
            self.state["imported"] = True
        if self.import_error is not None:
            COMMON._fail(self.import_error)

    def logout(self, _discovery, _session) -> None:
        self.logout_calls += 1

    def served_fingerprint(self) -> str:
        if self.sealed:
            COMMON._fail("bootstrap_client_sealed")
        return self.fingerprint

    def seal(self) -> None:
        self.sealed = True


class TLSHandler(http.server.BaseHTTPRequestHandler):
    """Record only public transport metadata from the loopback test server."""

    hosts: list[str] = []

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        self.__class__.hosts.append(self.headers.get("Host", ""))
        payload = b'{"success":true,"data":{}}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format: str, *_args: object) -> None:
        return None


class BootstrapTests(unittest.TestCase):
    """Exercise source ordering, transport separation, and sealed state."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.fixture = SUPPORT.Fixture(self.root)
        self.auth = self.root / "auth"
        self.auth.mkdir()
        (self.auth / "username").write_text("synthetic-user", encoding="ascii")
        (self.auth / "password").write_text("synthetic-password", encoding="ascii")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def config(self, **overrides):
        values = {"auth_directory": str(self.auth)}
        values.update(overrides)
        return self.fixture.config(**values)

    def inventory(self, config, *, display: str = "DSM", count: int = 3):
        rows = [
            COMMON.TargetSnapshot(
                "default-id",
                "DSM default",
                True,
                ("management",),
            ),
            COMMON.TargetSnapshot(
                config.target_id,
                config.target_description,
                False,
                (
                    {
                        "service": "certificate",
                        "owner": "system",
                        "isPkg": False,
                        "display_name": display,
                    },
                ),
            ),
        ]
        for index in range(count - 2):
            rows.append(
                COMMON.TargetSnapshot(
                    f"other-{index}",
                    f"Other {index}",
                    False,
                    (f"other-service-{index}",),
                )
            )
        return rows

    def source_fingerprint(self, config) -> str:
        return COMMON.load_source_snapshot(config).fingerprint

    def test_untrusted_wrong_name_bootstrap_accepts_and_strict_rejects(self) -> None:
        wrong = SUPPORT.Fixture(self.root / "wrong", hostname="wrong.example")
        config = wrong.config(auth_directory=str(self.auth))
        server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        server_context.load_cert_chain(str(wrong.cert), str(wrong.key))
        sni: list[str | None] = []
        server_context.set_servername_callback(lambda _socket, name, _context: sni.append(name))
        TLSHandler.hosts = []
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), TLSHandler)
        server.socket = server_context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            bootstrap_client = BOOTSTRAP.BootstrapDsmClient(
                config, connect_host="127.0.0.1", connect_port=server.server_port
            )
            response = bootstrap_client._request("GET", "/webapi/query.cgi")
            self.assertIn(b"success", response)
            self.assertEqual(TLSHandler.hosts, ["nas.bohdy.sk"])
            self.assertEqual(sni, ["nas.bohdy.sk"])
            self.assertFalse(bootstrap_client.context.check_hostname)
            self.assertEqual(bootstrap_client.context.verify_mode, ssl.CERT_NONE)

            strict_client = BOOTSTRAP.StrictDsmClient(
                config, connect_host="127.0.0.1", connect_port=server.server_port
            )
            with self.assertRaisesRegex(COMMON.ReconcileError, "dsm_tls_verification_failed"):
                strict_client.served_fingerprint()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_bad_source_rejects_before_client_or_auth(self) -> None:
        bad = SUPPORT.Fixture(self.root / "bad", hostname="wrong.example")
        config = bad.config(auth_directory=str(self.auth), target_id="stable-id")
        factories = []

        def client_factory(_config):
            factories.append(True)
            raise AssertionError("network client was created before source validation")

        with self.assertRaisesRegex(COMMON.ReconcileError, "source_tls_invalid"):
            BOOTSTRAP.bootstrap(config, import_once=True, client_factory=client_factory)
        self.assertEqual(factories, [])

    def test_target_placeholder_rejects_before_client_or_auth(self) -> None:
        config = self.config(target_id=COMMON.ACTIVATION_PLACEHOLDER)
        factories = []

        def client_factory(_config):
            factories.append(True)
            raise AssertionError("client was created before pin validation")

        with self.assertRaisesRegex(COMMON.ReconcileError, "target_id_not_pinned"):
            BOOTSTRAP.bootstrap(config, import_once=True, client_factory=client_factory)
        self.assertEqual(factories, [])

    def test_inspect_is_read_only_and_emits_deterministic_public_metadata(self) -> None:
        config = self.config(target_id=COMMON.ACTIVATION_PLACEHOLDER)
        client = InventoryClient(
            config,
            list(reversed(self.inventory(config, display='Display "snowman ☃"'))),
        )
        output = BOOTSTRAP.bootstrap(config, client_factory=lambda _config: client)
        parsed = json.loads(output)
        self.assertEqual(
            [row["id"] for row in parsed["certificates"]],
            sorted(["default-id", "other-0", config.target_id]),
        )
        self.assertIn("\\u2603", output)
        self.assertNotIn("synthetic-sid", output)
        self.assertNotIn("synthetic-token", output)
        self.assertNotIn("synthetic-password", output)
        self.assertEqual(client.import_calls, 0)
        self.assertEqual(client.logout_calls, 1)
        self.assertFalse(client.sealed)

    def test_inspect_rejects_reflected_password_or_session_values(self) -> None:
        config = self.config(target_id=COMMON.ACTIVATION_PLACEHOLDER)
        reflected = self.inventory(config, display="synthetic-password")
        client = InventoryClient(config, reflected)
        with self.assertRaisesRegex(COMMON.ReconcileError, "inventory_private_reflection"):
            BOOTSTRAP.bootstrap(config, client_factory=lambda _config: client)
        self.assertEqual(client.logout_calls, 1)

    def test_inventory_output_bound_is_fixed_and_sanitized(self) -> None:
        config = self.config(target_id=COMMON.ACTIVATION_PLACEHOLDER)
        client = InventoryClient(config, self.inventory(config, count=3))
        with patch.object(BOOTSTRAP, "MAX_INVENTORY_OUTPUT_BYTES", 16):
            with self.assertRaisesRegex(COMMON.ReconcileError, "inventory_output_too_large"):
                BOOTSTRAP.bootstrap(config, client_factory=lambda _config: client)
        self.assertEqual(client.logout_calls, 1)

    def test_import_success_seals_bootstrap_and_uses_fresh_strict_logout_and_poll(self) -> None:
        config = self.config(target_id="stable-id", retry_count=4, retry_delay_seconds=0)
        certificates = self.inventory(config)
        unverified = InventoryClient(config, certificates)
        source_fingerprint = self.source_fingerprint(config)
        strict_clients: list[InventoryClient] = []

        def strict_factory(_config):
            client = InventoryClient(config, certificates, fingerprint=source_fingerprint)
            strict_clients.append(client)
            return client

        result = BOOTSTRAP.bootstrap(
            config,
            import_once=True,
            client_factory=lambda _config: unverified,
            strict_client_factory=strict_factory,
        )
        self.assertEqual(result, "imported")
        self.assertEqual(unverified.import_calls, 1)
        self.assertTrue(unverified.sealed)
        self.assertEqual(unverified.logout_calls, 0)
        self.assertEqual(len(strict_clients), 2)  # initial SID cleanup plus first poll
        self.assertEqual(strict_clients[0].logout_calls, 1)
        self.assertEqual(strict_clients[1].logout_calls, 1)
        with self.assertRaisesRegex(COMMON.ReconcileError, "bootstrap_client_sealed"):
            unverified.served_fingerprint()

    def test_direct_import_failure_seals_real_bootstrap_client(self) -> None:
        config = self.config(target_id="stable-id")
        client = BOOTSTRAP.BootstrapDsmClient(config, connect_host="127.0.0.1")
        with patch.object(
            COMMON.DsmClient,
            "import_certificate",
            side_effect=COMMON.ReconcileError("api_error"),
        ):
            with self.assertRaisesRegex(COMMON.ReconcileError, "api_error"):
                client.import_certificate(None, None, None)
        self.assertTrue(client._sealed)
        with self.assertRaisesRegex(COMMON.ReconcileError, "bootstrap_client_sealed"):
            client.served_fingerprint()
        with self.assertRaisesRegex(COMMON.ReconcileError, "bootstrap_client_sealed"):
            client.import_certificate(None, None, None)

    def test_import_error_is_sealed_and_post_failure_never_retries_import(self) -> None:
        config = self.config(target_id="stable-id", retry_count=4, retry_delay_seconds=0)
        certificates = self.inventory(config)
        unverified = InventoryClient(config, certificates, import_error="api_error")
        strict_clients: list[InventoryClient] = []
        sleeps: list[float] = []

        def strict_factory(_config):
            client = InventoryClient(config, certificates, fingerprint="old")
            strict_clients.append(client)
            return client

        # The import envelope is the primary outcome even when strict polling
        # also proves that the old leaf is still served.
        with self.assertRaisesRegex(COMMON.ReconcileError, "api_error"):
            BOOTSTRAP.bootstrap(
                config,
                import_once=True,
                client_factory=lambda _config: unverified,
                strict_client_factory=strict_factory,
                sleep=sleeps.append,
            )
        self.assertEqual(unverified.import_calls, 1)
        self.assertTrue(unverified.sealed)
        self.assertEqual(unverified.logout_calls, 0)
        self.assertEqual(len(strict_clients), 5)  # cleanup plus four bounded polls
        self.assertEqual(len(sleeps), 3)
        self.assertTrue(all(client.import_calls == 0 for client in strict_clients))

    def test_mutate_then_import_error_stays_failed_even_when_strict_state_matches(self) -> None:
        config = self.config(target_id="stable-id", retry_count=2, retry_delay_seconds=0)
        certificates = self.inventory(config)
        state = {"imported": False}
        unverified = InventoryClient(
            config,
            certificates,
            import_error="api_error",
            state=state,
            mutate_then_error=True,
        )
        strict_clients: list[InventoryClient] = []
        source_fingerprint = self.source_fingerprint(config)

        def strict_factory(_config):
            # The strict view represents DSM having committed the mutation
            # before returning the fixed API error envelope.
            client = InventoryClient(
                config,
                certificates,
                fingerprint=source_fingerprint,
                state=state,
            )
            strict_clients.append(client)
            return client

        with self.assertRaisesRegex(COMMON.ReconcileError, "api_error"):
            BOOTSTRAP.bootstrap(
                config,
                import_once=True,
                client_factory=lambda _config: unverified,
                strict_client_factory=strict_factory,
            )
        self.assertEqual(unverified.import_calls, 1)
        self.assertTrue(unverified.sealed)
        self.assertTrue(state["imported"])
        self.assertEqual(len(strict_clients), 2)
        self.assertTrue(all(client.import_calls == 0 for client in strict_clients))

    def test_manifest_keeps_credentialed_wrapper_staged_but_inactive(self) -> None:
        job = (ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/job.yaml").read_text()
        cron = (ROOT / "kubernetes/flux/infrastructure/nas-tls/delivery/cronjob.yaml").read_text()
        kustomization = (ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/kustomization.yaml").read_text()
        self.assertIn("name: nas-tls-bootstrap-inspect-v1", job)
        self.assertIn("/bootstrap/nas_tls_bootstrap.py", job)
        self.assertIn("name: nas-tls-bootstrap", job)
        self.assertIn("configMapGenerator:", kustomization)
        self.assertIn("  - path-preflight-job.yaml", kustomization)
        self.assertIn("nas_tls_path_preflight.py", kustomization)
        self.assertNotIn("  - job.yaml", kustomization)
        self.assertNotIn("nas_tls_bootstrap.py", kustomization)
        self.assertNotIn("nas_tls_bootstrap.py", cron)
        self.assertNotIn("name: nas-tls-bootstrap", cron)

    def test_rendered_path_preflight_job_is_retained_without_automatic_recreation(self) -> None:
        """Keep terminal path evidence without automatic recreation or credentials."""

        result = subprocess.run(
            [
                "kubectl",
                "kustomize",
                str(ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap"),
            ],
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
            and "name: nas-tls-path-preflight-v1" in document
        ]
        self.assertEqual(len(jobs), 1)
        self.assertNotIn("nas-tls-bootstrap-inspect-v1", result.stdout)
        self.assertNotIn("nas_tls_bootstrap.py", result.stdout)
        job = jobs[0]
        for automatic_recreation_field in (
            "ttlSecondsAfterFinished:",
            "generateName:",
            "force:",
            "schedule:",
            "jobTemplate:",
        ):
            self.assertNotIn(automatic_recreation_field, job)
        for protected_field in (
            "backoffLimit: 0",
            "activeDeadlineSeconds: 300",
            "restartPolicy: Never",
            "automountServiceAccountToken: false",
            "runAsNonRoot: true",
            "readOnlyRootFilesystem: true",
            "mountPath: /path-preflight",
            "name: nas-tls-path-preflight",
            "app.kubernetes.io/name: nas-tls-delivery",
        ):
            self.assertIn(protected_field, job)
        for credential_or_source_field in (
            "secretName:",
            "source-certificate",
            "dsm-auth",
            "mountPath: /source",
            "mountPath: /auth",
            "mountPath: /etc/nas-tls",
            "serviceAccountName:",
        ):
            self.assertNotIn(credential_or_source_field, job)

    def test_manifests_keep_both_internal_aliases_and_new_certificate_order(self) -> None:
        job = (ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/job.yaml").read_text()
        preflight = (
            ROOT / "kubernetes/flux/infrastructure/nas-tls/bootstrap/path-preflight-job.yaml"
        ).read_text()
        cron = (ROOT / "kubernetes/flux/infrastructure/nas-tls/delivery/cronjob.yaml").read_text()
        certificate = (ROOT / "kubernetes/flux/infrastructure/nas-tls/issue/certificate.yaml").read_text()
        self.assertIn("- nas.bohdy.sk\n            - nas.bohdal.name", job)
        self.assertIn("- nas.bohdy.sk\n            - nas.bohdal.name", preflight)
        self.assertIn("- nas.bohdy.sk\n                - nas.bohdal.name", cron)
        self.assertIn("- nas.bohdy.sk\n    - nas.bohdal.name", certificate)
        self.assertEqual(certificate.count("    - nas."), 2)

    def test_internal_dns_keeps_compatibility_a_and_canonical_ptr(self) -> None:
        source_zone = (
            ROOT / "kubernetes/flux/infrastructure/dns/src/coredns/zones/bohdal.name.zone"
        ).read_text()
        canonical_zone = (
            ROOT / "kubernetes/flux/infrastructure/dns/src/coredns/zones/bohdy.sk.zone"
        ).read_text()
        reverse_zone = (
            ROOT / "kubernetes/flux/infrastructure/dns/src/coredns/zones/100.1.10.in-addr.arpa.zone"
        ).read_text()
        rendered = (
            ROOT / "kubernetes/flux/infrastructure/dns/rendered/coredns/zones-configmap.yaml"
        ).read_text()
        corefile = (ROOT / "kubernetes/flux/infrastructure/dns/src/coredns/corefile").read_text()
        self.assertIn("nas    IN A  10.1.100.10", source_zone)
        self.assertIn("nas IN A  10.1.100.10", canonical_zone)
        self.assertIn("@   IN NS dns.bohdal.name.", canonical_zone)
        self.assertIn("10 IN PTR nas.bohdy.sk.", reverse_zone)
        self.assertIn("bohdy.sk.zone", rendered)
        self.assertIn("10 IN PTR nas.bohdy.sk.", rendered)
        self.assertIn("file /zones/bohdy.sk.zone bohdy.sk", corefile)


if __name__ == "__main__":
    unittest.main()
