#!/usr/bin/env python3
"""Normalize repository Markdown to one physical line per paragraph or list item."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


# Treat these block starts as standalone Markdown constructs rather than prose
# that should be joined onto one physical line.
FENCE_RE = re.compile(r"^\s*```")
HEADING_RE = re.compile(r"^#{1,6}\s+")
LIST_RE = re.compile(r"^\s*(?:[-+*]|\d+\.)\s+")
HR_RE = re.compile(r"^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$")
TABLE_RE = re.compile(r"^\|")
BLOCKQUOTE_RE = re.compile(r"^\s*>")
HTML_RE = re.compile(r"^\s*<")


def is_passthrough_line(line: str) -> bool:
    """Return whether a line should be preserved as-is outside prose blocks."""

    stripped = line.strip()
    if not stripped:
        return False

    return any(
        pattern.match(line)
        for pattern in (HEADING_RE, HR_RE, TABLE_RE, BLOCKQUOTE_RE, HTML_RE)
    )


def is_joinable_block_start(line: str) -> bool:
    """Return whether a line starts a prose block that may absorb continuations."""

    return bool(LIST_RE.match(line))


def normalize_markdown(text: str) -> str:
    """Rewrite wrapped Markdown prose so each block becomes one physical line."""

    normalized_lines: list[str] = []
    current_block: str | None = None
    in_fence = False

    def flush_current_block() -> None:
        nonlocal current_block
        if current_block is not None:
            normalized_lines.append(current_block.rstrip())
            current_block = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()

        # Preserve fenced code blocks verbatim so code formatting stays
        # untouched by the prose normalizer.
        if FENCE_RE.match(line):
            flush_current_block()
            normalized_lines.append(line)
            in_fence = not in_fence
            continue

        if in_fence:
            normalized_lines.append(line)
            continue

        if not line.strip():
            flush_current_block()
            if normalized_lines and normalized_lines[-1] == "":
                continue
            normalized_lines.append("")
            continue

        if is_passthrough_line(line):
            flush_current_block()
            normalized_lines.append(line)
            continue

        if is_joinable_block_start(line):
            flush_current_block()
            current_block = line
            continue

        # Join paragraph continuations and wrapped list-item continuations with
        # a single separating space while preserving the original leading text.
        if current_block is None:
            current_block = line
        else:
            current_block = f"{current_block.rstrip()} {line.strip()}"

    flush_current_block()

    return "\n".join(normalized_lines).rstrip() + "\n"


def process_file(path: pathlib.Path, write: bool) -> bool:
    """Normalize one Markdown file and optionally write the updated content."""

    original = path.read_text(encoding="utf-8")
    normalized = normalize_markdown(original)

    if normalized == original:
        return False

    if write:
        path.write_text(normalized, encoding="utf-8")

    return True


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for check or write mode."""

    parser = argparse.ArgumentParser(
        description="Normalize Markdown to one physical line per paragraph or list item."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Rewrite files in place instead of only checking them.",
    )
    parser.add_argument("paths", nargs="+", help="Markdown files to check or rewrite.")
    return parser.parse_args()


def main() -> int:
    """Run the Markdown normalizer in check or write mode."""

    args = parse_args()
    changed_paths: list[str] = []

    for raw_path in args.paths:
        path = pathlib.Path(raw_path)
        if process_file(path, write=args.write):
            changed_paths.append(raw_path)

    if not changed_paths:
        return 0

    if args.write:
        for changed_path in changed_paths:
            print(f"normalized {changed_path}")
        return 0

    for changed_path in changed_paths:
        print(f"Markdown needs normalization: {changed_path}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
