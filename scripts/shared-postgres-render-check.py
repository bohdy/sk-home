#!/usr/bin/env python3
"""Check the rendered Cluster's reserved-role bootstrap contract without credentials."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


CLUSTER_NAME = "shared-postgres"
ROLE_COMMENT = "Special user for streaming replication created by CloudNativePG"
EXPECTED_ACL_ORDER = (
    "REVOKE CONNECT ON DATABASE postgres FROM PUBLIC",
    "GRANT CONNECT ON DATABASE postgres TO streaming_replica",
    "REVOKE CONNECT ON DATABASE template1 FROM PUBLIC",
)


def _cluster_document(rendered: str) -> str:
    """Select the one public Cluster document from kubectl's rendered stream."""

    documents = re.split(r"^---\s*$", rendered, flags=re.MULTILINE)
    matches = [
        document
        for document in documents
        if re.search(r"^kind: Cluster\s*$", document, flags=re.MULTILINE)
        and re.search(r"^  name: shared-postgres\s*$", document, flags=re.MULTILINE)
        and re.search(r"^  namespace: postgres\s*$", document, flags=re.MULTILINE)
    ]
    if len(matches) != 1:
        raise ValueError("rendered shared PostgreSQL Cluster identity is not unique")
    return matches[0]


def _post_init_sql(document: str) -> list[str]:
    """Extract only the rendered initdb.postInitSQL list in field order."""

    marker = "      postInitSQL:\n"
    start = document.find(marker)
    if start < 0:
        raise ValueError("rendered Cluster has no initdb postInitSQL")
    lines = document[start + len(marker) :].splitlines()
    entries: list[str] = []
    block: list[str] | None = None

    def flush() -> None:
        nonlocal block
        if block is not None:
            entries.append("\n".join(block).rstrip())
            block = None

    for line in lines:
        item = re.fullmatch(r"      - (.*)", line)
        if item:
            flush()
            value = item.group(1)
            if value in {"|", "|-", "|+"}:
                block = []
            else:
                entries.append(value)
            continue
        if block is not None:
            if line.startswith("        "):
                block.append(line[8:])
                continue
            if not line.strip():
                block.append("")
                continue
            flush()
            break
        if line.startswith("      ") and line.strip():
            break
        if line.strip():
            raise ValueError("unexpected indentation in rendered postInitSQL")
    flush()
    return entries


def _check_role_sql(value: str) -> None:
    """Require the guarded CNPG-compatible creation and exact role comment."""

    normalized = re.sub(r"\s+", " ", value).strip()
    required = (
        r"^DO \$\$ BEGIN IF NOT EXISTS \("
        r" SELECT 1 FROM pg_catalog\.pg_roles WHERE rolname = 'streaming_replica' "
        r"\) THEN CREATE ROLE streaming_replica LOGIN REPLICATION; "
        r"COMMENT ON ROLE streaming_replica IS '"
        + re.escape(ROLE_COMMENT)
        + r"'; END IF; END; \$\$;$"
    )
    if not re.fullmatch(required, normalized):
        raise ValueError("reserved streaming role bootstrap SQL does not match the reviewed contract")


def check_rendered_cluster(path: Path) -> None:
    """Validate role creation, public revocation, and internal grant ordering."""

    rendered = path.read_text(encoding="utf-8")
    sql = _post_init_sql(_cluster_document(rendered))
    if len(sql) != 4:
        raise ValueError("rendered postInitSQL entry count changed")
    _check_role_sql(sql[0])
    if tuple(sql[1:]) != EXPECTED_ACL_ORDER:
        raise ValueError("rendered reserved-role ACL order changed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rendered_cluster", type=Path)
    args = parser.parse_args()
    try:
        check_rendered_cluster(args.rendered_cluster)
    except (OSError, ValueError):
        raise SystemExit("Shared PostgreSQL rendered bootstrap contract failed") from None
    print("Shared PostgreSQL rendered bootstrap contract passed semantic checks.")


if __name__ == "__main__":
    main()
