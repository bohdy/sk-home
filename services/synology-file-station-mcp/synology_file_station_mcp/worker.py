"""Isolate untrusted document/image decoders from credentials and networking."""

from __future__ import annotations

import json
import logging
import resource
import socket
import sys
from pathlib import Path

from .server import (
    Limits,
    _convert_document_local,
    _image_content_local,
    _pdf_page_local,
)


def main() -> None:
    """Accept only adapter-owned source/config files and bounded JSON output."""
    logging.disable(logging.CRITICAL)
    config = json.loads(Path(sys.argv[2]).read_text())
    limits = Limits(**config["limits"])
    # This is defense in depth alongside the pod memory/scratch limits. No
    # subprocess receives the parent credentials or opens network connections.
    # MarkItDown's Office converters import numerical libraries that can
    # reserve more than 512 MiB even for a tiny document. Keep the worker
    # bounded below the pod's 768 MiB memory limit while leaving enough room
    # for those imports and one parser operation.
    resource.setrlimit(resource.RLIMIT_AS, (704 * 1024 * 1024, 704 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(
        resource.RLIMIT_FSIZE, (limits.temp_disk_bytes, limits.temp_disk_bytes)
    )
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))

    class OfflineSocket(socket.socket):
        """Deny parser-initiated network calls even if a converter tries one."""

        def connect(self, *_args: object, **_kwargs: object) -> None:
            raise OSError("Parser networking is disabled")

        def connect_ex(self, *_args: object, **_kwargs: object) -> int:
            raise OSError("Parser networking is disabled")

    socket.socket = OfflineSocket
    data = Path(sys.argv[1]).read_bytes()
    try:
        if config["kind"] == "document":
            result = _convert_document_local(
                data, "source" + config["extension"], limits
            )
        elif config["kind"] == "image":
            result = _image_content_local(data, limits).model_dump(
                mode="json", by_alias=True
            )
        elif config["kind"] == "pdf":
            result = _pdf_page_local(data, config["page"], limits).model_dump(
                mode="json", by_alias=True
            )
        else:
            raise ValueError("Unsupported parser operation")
        encoded = json.dumps({"result": result}, ensure_ascii=False).encode()
        if len(encoded) > limits.output_bytes * 4 // 3 + 4096:
            raise ValueError("Output limit")
        sys.stdout.buffer.write(encoded)
    except Exception:  # noqa: BLE001 -- parser failures must never expose document content.
        # Raw parser errors can include payloads and filenames. Never emit them.
        sys.stdout.write('{"error":"parser_rejected"}')


if __name__ == "__main__":
    main()
