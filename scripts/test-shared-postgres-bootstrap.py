"""Credential-free safety tests; no live CLI invocation or infrastructure access."""
import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch
import json

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).with_name("shared-postgres-bootstrap.py"))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class BootstrapTests(unittest.TestCase):
    def test_quotes(self):
        for raw in ("token", "'token'", '\"token\"'):
            self.assertEqual(b.token_value(raw), "token")
        for raw in ("", "'token", "token'", '\"token\'', "''", "'\"token\"'"):
            with self.assertRaises(b.BootstrapError):
                b.token_value(raw)

    def test_unique(self):
        for rows in ([], [{"key": "x"}, {"key": "x"}]):
            with self.assertRaises(b.BootstrapError):
                b.unique(rows, "key", "x")

    def run_bootstrap(self, existing=None, apply=False, race=False, uid="approved-uid", stored_change=None):
        calls = []
        created = None
        def runner(argv, env=None, payload=None):
            nonlocal created
            calls.append((argv, payload))
            if argv[0] == "bws":
                self.assertNotIn("--access-token", argv)
                self.assertNotIn("BWS_SERVER_URL", env)
                config = Path(env["BWS_CONFIG_FILE"]).read_text()
                self.assertIn('state_opt_out = "true"', config)
                self.assertNotIn("synthetic-password", config)
                if "project" in argv:
                    return json.dumps([{"name": "sk-home", "id": "synthetic-id"}])
                return json.dumps([{"key": "LITELLM_POSTGRES_PASSWORD", "projectId": "synthetic-id", "value": "synthetic-password"}])
            self.assertIsNotNone(env)
            self.assertFalse(any(key.startswith("BWS_") for key in env))
            self.assertEqual(env.get("KUBECTL_SYNTHETIC_SETTING"), "preserved")
            if "namespace" in argv:
                return json.dumps({"metadata": {"name": "postgres", "uid": "approved-uid"}})
            if "get" in argv:
                stored = created if created is not None else existing
                return json.dumps(stored) if stored is not None else ""
            if race:
                raise b.BootstrapError("External command failed; payload suppressed")
            self.assertEqual(json.loads(payload), b.expected_secret("synthetic-password"))
            created = json.loads(payload)
            if stored_change:
                created.update(stored_change)
            return "secret/litellm-postgres-auth"
        with patch.dict(os.environ, {"BWS_ACCESS_TOKEN": "synthetic-token", "BWS_SERVER_URL": "invalid", "BWS_OTHER_CREDENTIAL": "synthetic-extra", "KUBECTL_SYNTHETIC_SETTING": "preserved"}):
            result = b.bootstrap("synthetic-kubeconfig", uid, apply, runner)
        return result, calls

    def test_default_never_mutates(self):
        _, calls = self.run_bootstrap()
        self.assertTrue(all(payload is None for _, payload in calls))

    def test_existing_is_unchanged(self):
        _, calls = self.run_bootstrap(b.expected_secret("synthetic-password"), True)
        self.assertFalse(any("create" in argv for argv, _ in calls))

    def test_mismatch_refuses(self):
        for change in ({"type": "Opaque"}, {"data": {}}, {"metadata": {"name": "litellm-postgres-auth", "namespace": "postgres", "labels": {"cnpg.io/reload": "false"}}}):
            existing = b.expected_secret("synthetic-password")
            existing.update(change)
            with self.assertRaises(b.BootstrapError):
                self.run_bootstrap(existing, True)

    def test_wrong_cluster_namespace_refuses(self):
        with self.assertRaises(b.BootstrapError):
            self.run_bootstrap(apply=True, uid="other-cluster-uid")

    def test_create_only_and_race(self):
        _, calls = self.run_bootstrap(apply=True)
        self.assertEqual(sum("create" in argv for argv, _ in calls), 1)
        self.assertFalse(any("apply" in argv or "patch" in argv for argv, _ in calls))
        with self.assertRaises(b.BootstrapError):
            self.run_bootstrap(apply=True, race=True)

    def test_kubectl_does_not_inherit_bitwarden_environment(self):
        # Every fake Kubernetes invocation checks sanitized env and normal settings.
        self.run_bootstrap(apply=True)

    def test_post_create_mismatch_refuses(self):
        for change in ({"type": "Opaque"}, {"data": {}},
                       {"metadata": {"name": "litellm-postgres-auth", "namespace": "postgres",
                                     "labels": {"cnpg.io/reload": "false"}}},
                       {"metadata": {"name": "litellm-postgres-auth", "namespace": "postgres",
                                     "labels": {"cnpg.io/reload": "true"},
                                     "ownerReferences": [{"name": "other-owner"}]}}):
            with self.assertRaises(b.BootstrapError) as error:
                self.run_bootstrap(apply=True, stored_change=change)
            self.assertNotIn("synthetic-password", str(error.exception))

    def test_cli_errors_are_redacted(self):
        fake = __import__("subprocess").CompletedProcess([], 1, "synthetic-password", "synthetic-token")
        with patch.object(b.subprocess, "run", return_value=fake):
            with self.assertRaises(b.BootstrapError) as error:
                b.execute(["synthetic"])
        self.assertNotIn("synthetic", str(error.exception))


if __name__ == "__main__":
    unittest.main()
