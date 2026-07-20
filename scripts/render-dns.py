#!/usr/bin/env python3
"""Render the GitOps DNS manifests from the human-edited source tree."""

from __future__ import annotations

import argparse
import datetime as dt
import filecmp
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DNS_ROOT = REPO_ROOT / "kubernetes/flux/infrastructure/dns"
SRC_DIR = DNS_ROOT / "src"
RENDERED_DIR = DNS_ROOT / "rendered"
ZONE_DIR = SRC_DIR / "coredns/zones"
SERIAL_RE = re.compile(r"(?P<indent>\s*)(?P<serial>\d{10})(?P<suffix>\s*;\s*serial)")


def run_git_show(path: Path) -> str | None:
    """Return a file from HEAD, or None when the file is not tracked yet."""
    rel_path = path.relative_to(REPO_ROOT).as_posix()
    proc = subprocess.run(
        ["git", "show", f"HEAD:{rel_path}"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout


def normalize_serials(content: str) -> str:
    """Ignore SOA serial values while comparing substantive zone changes."""
    return SERIAL_RE.sub(r"\g<indent><SERIAL>\g<suffix>", content)


def next_serial(current: str, today: str) -> str:
    """Return today's first serial, or the next sequence for today's serial."""
    if current.startswith(today):
        return f"{int(current) + 1:010d}"
    return f"{today}01"


def zone_serial(content: str) -> str:
    """Return the single SOA serial from a zone file."""
    matches = list(SERIAL_RE.finditer(content))
    if len(matches) != 1:
        raise ValueError("expected exactly one SOA serial marked with '; serial'")
    return matches[0].group("serial")


def set_zone_serial(content: str, serial: str) -> str:
    """Replace the single SOA serial in a zone file."""
    if len(list(SERIAL_RE.finditer(content))) != 1:
        raise ValueError("expected exactly one SOA serial marked with '; serial'")
    return SERIAL_RE.sub(
        lambda match: f"{match.group('indent')}{serial}{match.group('suffix')}",
        content,
        count=1,
    )


def changed_zone_files(explicit_files: list[Path]) -> list[tuple[Path, bool]]:
    """Find changed zone files and whether each file is new to Git."""
    candidates = explicit_files or sorted(ZONE_DIR.glob("*.zone"))
    changed: list[tuple[Path, bool]] = []
    for path in candidates:
        current = path.read_text()
        previous = run_git_show(path)
        if previous is None or normalize_serials(current) != normalize_serials(previous):
            changed.append((path, previous is None))
    return changed


def update_serials(check: bool, explicit_files: list[Path]) -> bool:
    """Update source zone serials, or report stale serials in check mode."""
    today = dt.date.today().strftime("%Y%m%d")
    stale = False
    for path, is_new in changed_zone_files(explicit_files):
        current = path.read_text()
        if is_new:
            expected_serial = f"{today}01"
        else:
            # Derive the expected serial from the committed baseline instead
            # of the working file so repeated renders remain idempotent.
            previous = run_git_show(path)
            if previous is None:
                raise ValueError(f"cannot read committed zone file: {path}")
            expected_serial = next_serial(zone_serial(previous), today)
        updated = set_zone_serial(current, expected_serial)
        did_update = updated != current
        if did_update:
            stale = True
            if not check:
                path.write_text(updated)
    return stale


def checksum(paths: list[Path]) -> str:
    """Hash file names and bytes so rollout annotations change predictably."""
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(SRC_DIR).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def yaml_block(value: str, indent: int) -> str:
    """Render a literal block scalar body with a fixed indentation."""
    prefix = " " * indent
    return "".join(
        "\n" if line == "" else f"{prefix}{line}\n"
        for line in value.splitlines()
    )


def render_configmap(name: str, namespace: str, entries: dict[str, str]) -> str:
    """Create a ConfigMap from file-like entries without requiring kubectl."""
    lines = [
        "apiVersion: v1\n",
        "kind: ConfigMap\n",
        "metadata:\n",
        f"  name: {name}\n",
        f"  namespace: {namespace}\n",
        "data:\n",
    ]
    for key, value in sorted(entries.items()):
        lines.append(f"  {key}: |\n")
        lines.append(yaml_block(value.rstrip("\n"), 4))
    return "".join(lines)


def copy_source_tree(target: Path) -> None:
    """Copy human-edited YAML and omit raw zone/Corefile inputs."""
    if target.exists():
        shutil.rmtree(target)
    for path in SRC_DIR.rglob("*"):
        if path.is_dir():
            continue
        rel = path.relative_to(SRC_DIR)
        if rel == Path("coredns/corefile") or rel.parts[:2] == ("coredns", "zones"):
            continue
        destination = target / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(path.read_text())


def render(target: Path) -> None:
    """Render generated ConfigMaps and checksum placeholders."""
    copy_source_tree(target)

    corefile = (SRC_DIR / "coredns/corefile").read_text()
    zones = {path.name: path.read_text() for path in sorted(ZONE_DIR.glob("*.zone"))}

    (target / "coredns/corefile-configmap.yaml").write_text(
        render_configmap("coredns-corefile", "dns-system", {"Corefile": corefile})
    )
    (target / "coredns/zones-configmap.yaml").write_text(
        render_configmap("coredns-zones", "dns-system", zones)
    )

    replacements = {
        "__BLOCKY_CONFIG_CHECKSUM__": checksum([SRC_DIR / "blocky/configmap.yaml"]),
        "__COREDNS_COREFILE_CHECKSUM__": checksum([SRC_DIR / "coredns/corefile"]),
        "__COREDNS_ZONES_CHECKSUM__": checksum(sorted(ZONE_DIR.glob("*.zone"))),
    }
    for path in target.rglob("*.yaml"):
        content = path.read_text()
        for placeholder, value in replacements.items():
            content = content.replace(placeholder, value)
        path.write_text(content)


def directories_equal(left: Path, right: Path) -> bool:
    """Compare rendered trees by file contents and relative paths."""
    comparison = filecmp.dircmp(left, right)
    if comparison.left_only or comparison.right_only or comparison.diff_files:
        return False
    return all(
        directories_equal(left / subdir, right / subdir)
        for subdir in comparison.common_dirs
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when source serials or rendered manifests are stale",
    )
    parser.add_argument(
        "zone_files",
        nargs="*",
        type=Path,
        help="optional explicit zone files to consider for serial bumps",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    explicit_files = [
        path if path.is_absolute() else (REPO_ROOT / path)
        for path in args.zone_files
    ]

    stale_serials = update_serials(args.check, explicit_files)
    if args.check and stale_serials:
        print("DNS zone serials are stale; run `mise run dns-render`.", file=sys.stderr)
        return 1

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            rendered = Path(tmp) / "rendered"
            render(rendered)
            if not RENDERED_DIR.exists() or not directories_equal(rendered, RENDERED_DIR):
                print("Rendered DNS manifests are stale; run `mise run dns-render`.", file=sys.stderr)
                return 1
    else:
        render(RENDERED_DIR)

    return 0


if __name__ == "__main__":
    sys.exit(main())
