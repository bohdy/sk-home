"""Run native Prometheus semantic checks for the committed NAS TLS VMRule.

The VMRule is the source of truth; this helper copies only its spec.groups into
a temporary Prometheus rule file before invoking promtool against public tests.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[1]
VM_RULES = REPOSITORY_ROOT / "kubernetes/flux/observability/nas-tls/vm-rules.yaml"
TEST_FIXTURE = REPOSITORY_ROOT / "tests/fixtures/nas-tls-alerts.test.yaml"


def convert_vm_rule_to_prometheus_rules(source: Path, destination: Path) -> None:
    """Extract only the native Prometheus groups from the committed VMRule."""

    lines = source.read_text(encoding="utf-8").splitlines(keepends=True)
    try:
        groups_index = next(
            index
            for index, line in enumerate(lines)
            if line.rstrip("\n") == "  groups:"
        )
    except StopIteration as error:
        raise ValueError("VMRule has no spec.groups block") from error

    converted: list[str] = []
    for line in lines[groups_index:]:
        # Removing exactly the VMRule spec indentation preserves every rule and expression.
        if line.startswith("  "):
            converted.append(line[2:])
        elif line.strip():
            raise ValueError("unexpected unindented content after spec.groups")
        else:
            converted.append(line)

    if not converted or converted[0].rstrip("\n") != "groups:":
        raise ValueError("VMRule groups conversion did not produce Prometheus rules")
    destination.write_text("".join(converted), encoding="utf-8")


def run_promtool(promtool: str, arguments: list[str], *, cwd: Path | None = None) -> None:
    """Run a promtool command while retaining its native diagnostics."""

    subprocess.run([promtool, *arguments], check=True, cwd=cwd)


def main() -> None:
    """Validate and semantically exercise the committed NAS TLS rule expressions."""

    promtool = shutil.which("promtool")
    if promtool is None:
        raise SystemExit("promtool is unavailable; run this check through mise")
    with tempfile.TemporaryDirectory(prefix="nas-tls-promtool-") as temporary:
        scratch = Path(temporary)
        rule_file = scratch / "nas-tls-rules.yaml"
        test_file = scratch / "nas-tls-alerts.test.yaml"
        convert_vm_rule_to_prometheus_rules(VM_RULES, rule_file)
        # The temporary directory contains only generated public rules and the committed fixture.
        shutil.copyfile(TEST_FIXTURE, test_file)
        run_promtool(promtool, ["check", "rules", str(rule_file)])
        run_promtool(promtool, ["test", "rules", test_file], cwd=scratch)
    print("NAS TLS VMRule passed promtool rule syntax and semantic unit tests.")


if __name__ == "__main__":
    main()
