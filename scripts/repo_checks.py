#!/usr/bin/env python3
"""Minimal repo-native formatting, linting, and validation for the scaffold."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
TEXT_SUFFIXES = {".md", ".yaml", ".yml"}
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def tracked_files() -> list[Path]:
    """Return tracked text files that the scaffold checks are responsible for."""
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [
        REPO_ROOT / rel_path
        for rel_path in result.stdout.splitlines()
        if Path(rel_path).suffix in TEXT_SUFFIXES
    ]


def normalize_text(text: str) -> str:
    """Apply safe text normalization without changing paragraph structure."""
    normalized_lines = [line.rstrip() for line in text.splitlines()]
    normalized = "\n".join(normalized_lines)
    return f"{normalized}\n"


def format_files() -> int:
    """Rewrite tracked Markdown and YAML files into a stable normalized form."""
    changed = 0
    for path in tracked_files():
        original = path.read_text()
        normalized = normalize_text(original)
        if normalized != original:
            path.write_text(normalized)
            changed += 1
    print(f"formatted {changed} file(s)")
    return 0


def relative(path: Path) -> str:
    """Render repo-relative paths in diagnostics."""
    return str(path.relative_to(REPO_ROOT))


def check_no_trailing_whitespace(path: Path, errors: list[str]) -> None:
    """Keep whitespace lint simple and explicit for text-heavy files."""
    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        if line.rstrip() != line:
            errors.append(f"{relative(path)}:{lineno}: trailing whitespace")


def check_final_newline(path: Path, errors: list[str]) -> None:
    """Require a trailing newline so formatting remains stable."""
    content = path.read_text()
    if not content.endswith("\n"):
        errors.append(f"{relative(path)}: missing trailing newline")


def check_markdown_links(path: Path, errors: list[str]) -> None:
    """Verify local Markdown links point at files that exist in the repo."""
    content = path.read_text()
    for match in MARKDOWN_LINK_RE.finditer(content):
        target = match.group(1)
        if "://" in target or target.startswith("#"):
            continue
        if target.startswith("mailto:"):
            continue
        clean_target = target.split("#", 1)[0]
        if not clean_target:
            continue
        if clean_target.startswith("/"):
            candidate = REPO_ROOT / clean_target.lstrip("/")
        else:
            candidate = (path.parent / clean_target).resolve()
        if not candidate.exists():
            errors.append(
                f"{relative(path)}: broken markdown link target '{target}'"
            )


def parse_frontmatter(path: Path, errors: list[str]) -> dict[str, str] | None:
    """Extract minimal skill frontmatter without adding external YAML deps."""
    content = path.read_text()
    if not content.startswith("---\n"):
        errors.append(f"{relative(path)}: missing YAML frontmatter start")
        return None
    try:
        _, raw_frontmatter, _ = content.split("---\n", 2)
    except ValueError:
        errors.append(f"{relative(path)}: malformed YAML frontmatter block")
        return None
    data: dict[str, str] = {}
    for lineno, line in enumerate(raw_frontmatter.splitlines(), start=2):
        if not line.strip():
            continue
        if ":" not in line:
            errors.append(f"{relative(path)}:{lineno}: invalid frontmatter line")
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()
    return data


def check_skill(path: Path, errors: list[str]) -> None:
    """Enforce the minimal structure the repo-local skill relies on."""
    frontmatter = parse_frontmatter(path, errors)
    if frontmatter is None:
        return
    for required_key in ("name", "description"):
        if required_key not in frontmatter or not frontmatter[required_key]:
            errors.append(f"{relative(path)}: missing frontmatter key '{required_key}'")
    body = path.read_text()
    for required_heading in (
        "## Documentation Sync",
        "## Quality Gates",
        "## Pull Request Content",
    ):
        if required_heading not in body:
            errors.append(f"{relative(path)}: missing heading '{required_heading}'")


def check_openai_yaml(path: Path, errors: list[str]) -> None:
    """Validate the current simple nested mapping format used by openai.yaml."""
    expected_lines = {
        "interface:",
        '  display_name: "Create sk-home PR"',
        '  short_description: "Format, lint, validate, then open a fully documented sk-home PR."',
        '  default_prompt: "Create a pull request for my current sk-home changes following repo workflow rules, including required formatting, linting, validation, and a PR body that summarizes and explains all changed code."',
    }
    actual_lines = {line for line in path.read_text().splitlines() if line}
    missing = expected_lines - actual_lines
    for line in sorted(missing):
        errors.append(f"{relative(path)}: missing expected YAML line '{line}'")


def lint_files() -> int:
    """Run repo-specific lint checks over tracked Markdown and YAML files."""
    errors: list[str] = []
    for path in tracked_files():
        check_no_trailing_whitespace(path, errors)
        check_final_newline(path, errors)
        if path.suffix == ".md":
            check_markdown_links(path, errors)
        if path.name == "SKILL.md":
            check_skill(path, errors)
        if path.name == "openai.yaml":
            check_openai_yaml(path, errors)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("lint passed")
    return 0


def validate_repo() -> int:
    """Run the higher-level repository integrity checks needed before PRs."""
    lint_status = lint_files()
    if lint_status != 0:
        return lint_status
    required_paths = [
        REPO_ROOT / ".codex/skills/sk-home-create-pr/SKILL.md",
        REPO_ROOT / ".codex/skills/sk-home-create-pr/agents/openai.yaml",
        REPO_ROOT / "AGENTS.md",
        REPO_ROOT / "README.md",
        REPO_ROOT / "Makefile",
        REPO_ROOT / "scripts/repo_checks.py",
    ]
    missing = [relative(path) for path in required_paths if not path.exists()]
    if missing:
        print(
            "missing required repo file(s): " + ", ".join(missing),
            file=sys.stderr,
        )
        return 1
    print("validation passed")
    return 0


def main(argv: list[str]) -> int:
    """Dispatch the stable repo-native check commands."""
    if len(argv) != 2 or argv[1] not in {"format", "lint", "validate"}:
        print("usage: repo_checks.py [format|lint|validate]", file=sys.stderr)
        return 2
    command = argv[1]
    if command == "format":
        return format_files()
    if command == "lint":
        return lint_files()
    return validate_repo()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
