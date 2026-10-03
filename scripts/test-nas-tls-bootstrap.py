"""Credential-free synthetic tests for the NAS TLS Secret bootstrap helper."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("nas-tls-bootstrap.py")
SPEC = importlib.util.spec_from_file_location("nas_tls_bootstrap", MODULE_PATH)
assert SPEC and SPEC.loader
BOOTSTRAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOOTSTRAP)


class BootstrapTests(unittest.TestCase):
    """Exercise the helper with synthetic Bitwarden and kubectl responses."""

    def setUp(self) -> None:
        self.project_id = "project-123"
        self.namespace_uid = "namespace-123"
        self.calls: list[tuple[list[str], str | None, dict[str, str]]] = []
        self.created: dict[str, object] | None = None

    def _runner(
        self,
        argv: list[str],
        *,
        env: dict[str, str] | None = None,
        payload: str | None = None,
        item: dict[str, object] | None = None,
        existing: dict[str, object] | None = None,
        race: bool = False,
        stored_change: dict[str, object] | None = None,
    ) -> str:
        """Return synthetic metadata while recording private call boundaries."""

        self.assertIsNotNone(env)
        safe_env = dict(env or {})
        self.calls.append((list(argv), payload, safe_env))
        if argv[0] == "bws":
            self.assertNotIn("--access-token", argv)
            self.assertIn("BWS_ACCESS_TOKEN", safe_env)
            self.assertIn("BWS_CONFIG_FILE", safe_env)
            self.assertNotIn("BWS_SERVER_URL", safe_env)
            config = Path(safe_env["BWS_CONFIG_FILE"]).read_text(encoding="ascii")
            self.assertIn('state_opt_out = "true"', config)
            self.assertNotIn("synthetic-password", config)
            if "project" in argv:
                return json.dumps([{"name": "sk-home", "id": self.project_id}])
            self.assertEqual(argv[-1], BOOTSTRAP.BITWARDEN_ITEM_ID)
            result = item or {
                "id": BOOTSTRAP.BITWARDEN_ITEM_ID,
                "key": BOOTSTRAP.BITWARDEN_ITEM_KEY,
                "projectId": self.project_id,
                "value": "synthetic-password",
            }
            return json.dumps(result)

        self.assertFalse(any(key.startswith("BWS_") for key in safe_env))
        if "namespace" in argv:
            return json.dumps(
                {
                    "metadata": {
                        "name": BOOTSTRAP.NAMESPACE_NAME,
                        "uid": self.namespace_uid,
                        "labels": dict(BOOTSTRAP.EXPECTED_NAMESPACE_LABELS),
                    }
                }
            )
        if "create" in argv:
            if race:
                raise BOOTSTRAP.BootstrapError(
                    "External command failed; payload suppressed"
                )
            self.assertIsNotNone(payload)
            created = json.loads(payload or "")
            self.assertEqual(
                created,
                BOOTSTRAP.expected_secret(BOOTSTRAP.BITWARDEN_USERNAME, "synthetic-password"),
            )
            self.created = created
            return "secret/nas-tls-dsm-auth"
        stored = self.created if self.created is not None else existing
        if stored is None:
            return ""
        if stored_change:
            stored = json.loads(json.dumps(stored))
            for key, value in stored_change.items():
                stored[key] = value
        return json.dumps(stored)

    def run_bootstrap(
        self,
        *,
        existing: dict[str, object] | None = None,
        apply: bool = False,
        race: bool = False,
        uid: str | None = None,
        item: dict[str, object] | None = None,
        stored_change: dict[str, object] | None = None,
    ) -> str:
        """Run with synthetic environment values and no subprocesses."""

        def runner(argv: list[str], env=None, payload=None):
            return self._runner(
                argv,
                env=env,
                payload=payload,
                existing=existing,
                race=race,
                item=item,
                stored_change=stored_change,
            )

        with patch.dict(
            os.environ,
            {
                "BWS_ACCESS_TOKEN": "'synthetic-token'",
                "BWS_SERVER_URL": "https://hostile.invalid",
                "BWS_OTHER_CREDENTIAL": "synthetic-extra",
                "KUBECTL_SYNTHETIC_SETTING": "preserved",
            },
        ):
            return BOOTSTRAP.bootstrap(
                "/synthetic/kubeconfig",
                uid or self.namespace_uid,
                apply=apply,
                runner=runner,
            )

    def test_token_normalization_requires_matching_pair(self) -> None:
        for raw in ("token", "'token'", '"token"'):
            self.assertEqual(BOOTSTRAP.token_value(raw), "token")
        for raw in ("", "'token", "token'", '"token\'', "''", "'\"token\"'"):
            with self.assertRaises(BOOTSTRAP.BootstrapError):
                BOOTSTRAP.token_value(raw)

    def test_default_is_read_only_and_sanitizes_kubernetes_environment(self) -> None:
        result = self.run_bootstrap()
        self.assertEqual(result, "Secret absent; preflight passed; no mutation")
        self.assertTrue(all(payload is None for _argv, payload, _env in self.calls))
        kubernetes_envs = [env for argv, _payload, env in self.calls if argv[0] == "kubectl"]
        self.assertTrue(kubernetes_envs)
        self.assertTrue(all(not key.startswith("BWS_") for env in kubernetes_envs for key in env))

    def test_existing_secret_is_verified_without_mutation(self) -> None:
        existing = BOOTSTRAP.expected_secret(BOOTSTRAP.BITWARDEN_USERNAME, "synthetic-password")
        self.assertEqual(self.run_bootstrap(existing=existing, apply=True), "Existing Secret verified; unchanged")
        self.assertFalse(any("create" in argv for argv, _payload, _env in self.calls))

    def test_namespace_identity_and_labels_are_required(self) -> None:
        with self.assertRaisesRegex(BOOTSTRAP.BootstrapError, "Expected namespace"):
            self.run_bootstrap(uid="other-namespace")

    def test_apply_is_atomic_create_only_and_postchecked(self) -> None:
        result = self.run_bootstrap(apply=True)
        self.assertEqual(result, "Reviewed application Secret created")
        self.assertEqual(sum("create" in argv for argv, _payload, _env in self.calls), 1)
        self.assertFalse(any("apply" in argv or "patch" in argv for argv, _payload, _env in self.calls))

    def test_race_or_postcreate_drift_fails_closed(self) -> None:
        with self.assertRaises(BOOTSTRAP.BootstrapError):
            self.run_bootstrap(apply=True, race=True)
        for change in (
            {"type": "kubernetes.io/basic-auth"},
            {"data": {}},
            {
                "metadata": {
                    "name": BOOTSTRAP.SECRET_NAME,
                    "namespace": BOOTSTRAP.NAMESPACE_NAME,
                    "labels": {"unexpected": "owner"},
                }
            },
            {
                "metadata": {
                    "name": BOOTSTRAP.SECRET_NAME,
                    "namespace": BOOTSTRAP.NAMESPACE_NAME,
                    "labels": dict(BOOTSTRAP.EXPECTED_SECRET_LABELS),
                    "ownerReferences": [{"name": "unexpected-owner"}],
                }
            },
        ):
            with self.assertRaises(BOOTSTRAP.BootstrapError) as error:
                self.run_bootstrap(apply=True, stored_change=change)
            self.assertNotIn("synthetic-password", str(error.exception))

    def test_bitwarden_item_identity_and_scalar_password_contract(self) -> None:
        for change in (
            {"id": "other-item"},
            {"key": "OTHER_ITEM"},
            {"projectId": "other-project"},
            {"value": ""},
            {"value": "password\nwith-control"},
            {"value": 42},
        ):
            item = {
                "id": BOOTSTRAP.BITWARDEN_ITEM_ID,
                "key": BOOTSTRAP.BITWARDEN_ITEM_KEY,
                "projectId": self.project_id,
                "value": "synthetic-password",
            }
            item.update(change)
            with self.assertRaises(BOOTSTRAP.BootstrapError):
                self.run_bootstrap(item=item)

    def test_bitwarden_source_is_fixed_and_username_is_not_selectable(self) -> None:
        self.run_bootstrap()
        secret_calls = [
            argv for argv, _payload, _env in self.calls if argv[0] == "bws" and "secret" in argv
        ]
        self.assertEqual(len(secret_calls), 1)
        self.assertEqual(secret_calls[0][-1], BOOTSTRAP.BITWARDEN_ITEM_ID)
        self.assertEqual(BOOTSTRAP.BITWARDEN_USERNAME, "synology-csi")

    def test_subprocess_failures_timeout_and_output_are_redacted(self) -> None:
        with patch.object(
            BOOTSTRAP.subprocess,
            "run",
            side_effect=RuntimeError("synthetic-password synthetic-token"),
        ):
            with self.assertRaises(BOOTSTRAP.BootstrapError) as error:
                BOOTSTRAP.execute(["synthetic"])
        self.assertNotIn("synthetic-password", str(error.exception))
        with patch.object(
            BOOTSTRAP.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                [], 0, "x" * (BOOTSTRAP.MAX_COMMAND_OUTPUT_BYTES + 1), "synthetic-token"
            ),
        ):
            with self.assertRaises(BOOTSTRAP.BootstrapError) as error:
                BOOTSTRAP.execute(["synthetic"])
        self.assertNotIn("synthetic-token", str(error.exception))
        with patch.object(
            BOOTSTRAP.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(["synthetic"], 1),
        ):
            with self.assertRaises(BOOTSTRAP.BootstrapError):
                BOOTSTRAP.execute(["synthetic"])


if __name__ == "__main__":
    unittest.main()
