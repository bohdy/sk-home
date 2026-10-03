#!/usr/bin/env python3
"""Create only the reviewed application Secret; never rotate or emit credentials."""
import argparse
import base64
import json
import os
import subprocess
import tempfile
from pathlib import Path


class BootstrapError(Exception):
    """Fixed diagnostics prevent subprocess payloads entering operator output."""


def token_value(raw):
    # Only a complete matching wrapper is normalization, not arbitrary stripping.
    if not raw:
        raise BootstrapError("Bitwarden token unavailable")
    if raw[0] in "\"'" or raw[-1] in "\"'":
        if len(raw) < 3 or raw[0] != raw[-1]:
            raise BootstrapError("Bitwarden token quoting invalid")
        raw = raw[1:-1]
    if not raw or raw[0] in "\"'" or raw[-1] in "\"'":
        raise BootstrapError("Bitwarden token quoting invalid")
    return raw


def unique(rows, field, value):
    selected = [r for r in rows if r.get(field) == value]
    if len(selected) != 1:
        raise BootstrapError("Bitwarden identity is missing or ambiguous")
    return selected[0]


def execute(argv, env=None, payload=None):
    # Both streams stay private, including CLI errors that may echo Secret data.
    try:
        result = subprocess.run(argv, input=payload, capture_output=True,
                                env=env, text=True, timeout=60, check=False)
        if result.returncode:
            raise BootstrapError("External command failed; payload suppressed")
        return result.stdout
    except (OSError, subprocess.TimeoutExpired):
        raise BootstrapError("External command unavailable; payload suppressed") from None


def document(raw):
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        raise BootstrapError("Invalid private response; payload suppressed") from None


def expected_secret(password):
    return {"apiVersion": "v1", "kind": "Secret",
            "metadata": {"name": "litellm-postgres-auth", "namespace": "postgres",
                         "labels": {"cnpg.io/reload": "true"}},
            "type": "kubernetes.io/basic-auth",
            "data": {"username": base64.b64encode(b"litellm").decode(),
                     "password": base64.b64encode(password.encode()).decode()}}


def verify_secret(existing, expected):
    # Reject collisions and drift instead of modifying an existing owner's Secret.
    meta = existing.get("metadata", {})
    if (meta.get("name") != "litellm-postgres-auth" or
            meta.get("namespace") != "postgres" or
            meta.get("labels", {}).get("cnpg.io/reload") != "true" or
            meta.get("ownerReferences") or existing.get("type") != expected["type"] or
            existing.get("data") != expected["data"]):
        raise BootstrapError("Existing Secret differs; refusing rotation or adoption")


def bootstrap(kubeconfig, namespace_uid, apply=False, runner=execute):
    # Kubernetes subprocesses never inherit Bitwarden credentials or settings.
    kube_env = {key: value for key, value in os.environ.items() if not key.startswith("BWS_")}
    env = dict(os.environ)
    env["BWS_ACCESS_TOKEN"] = token_value(env.get("BWS_ACCESS_TOKEN", ""))
    # Use isolated, non-secret configuration to forbid the BWS encrypted-state cache.
    # No password, token or CLI output is written to this temporary directory.
    with tempfile.TemporaryDirectory(prefix="postgres-bws-") as directory:
        config = Path(directory) / "config"
        config.write_text('[profiles.default]\nserver_base = "https://api.bitwarden.com"\nserver_api = "https://api.bitwarden.com"\nserver_identity = "https://identity.bitwarden.com"\nstate_opt_out = "true"\n')
        config.chmod(0o600)
        env["BWS_CONFIG_FILE"] = str(config)
        env.pop("BWS_PROFILE", None)
        env.pop("BWS_SERVER_URL", None)
        bws = ["bws", "--profile", "default", "--config-file", str(config), "--output", "json"]
        projects = document(runner(bws + ["project", "list"], env=env))
        project = unique(projects, "name", "sk-home")
        project_id = project.get("id")
        if not isinstance(project_id, str) or not project_id:
            raise BootstrapError("Bitwarden project identity invalid")
        rows = document(runner(bws + ["secret", "list", project_id], env=env))
        item = unique(rows, "key", "LITELLM_POSTGRES_PASSWORD")
        password = item.get("value")
        if item.get("projectId") != project_id or not isinstance(password, str) or not password:
            raise BootstrapError("Bitwarden Secret identity or value invalid")
        expected = expected_secret(password)
        kube = ["kubectl", "--kubeconfig", kubeconfig]
        namespace = document(runner(kube + ["get", "namespace", "postgres", "-o", "json"], env=kube_env))
        if (namespace.get("metadata", {}).get("name") != "postgres" or
                namespace.get("metadata", {}).get("uid") != namespace_uid):
            raise BootstrapError("Expected namespace unavailable")
        raw = runner(kube + ["-n", "postgres", "get", "secret", "litellm-postgres-auth",
                             "--ignore-not-found", "-o", "json"], env=kube_env)
        if raw.strip():
            verify_secret(document(raw), expected)
            return "Existing Secret verified; unchanged"
        if not apply:
            return "Secret absent; preflight passed; no mutation"
        # Create is atomic: a concurrent creator causes failure, never overwrite.
        runner(kube + ["create", "-f", "-", "-o", "name"], env=kube_env, payload=json.dumps(expected))
        # Admission or concurrent mutation must not turn creation into false success.
        stored = document(runner(kube + ["-n", "postgres", "get", "secret",
                                        "litellm-postgres-auth", "-o", "json"], env=kube_env))
        verify_secret(stored, expected)
        return "Reviewed application Secret created"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--namespace-uid", required=True,
                        help="UID independently verified in approved target cluster")
    parser.add_argument("--apply-secret", action="store_true",
                        help="Create absent Secret only; requires production approval")
    args = parser.parse_args()
    try:
        print(bootstrap(args.kubeconfig, args.namespace_uid, args.apply_secret))
        return 0
    except Exception:
        # Even unexpected parsing/type failures must not leak values or tracebacks.
        print("Bootstrap refused; private payloads suppressed", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
