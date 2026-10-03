"""A constrained, read-only MCP facade over Synology File Station.

The adapter deliberately keeps the Synology session and downloaded content in
memory or short-lived temporary files.  It never writes credentials or session
IDs to disk, follows redirects, accepts arbitrary URLs, or exposes remote API
error bodies to MCP callers.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import functools
import io
import json
import logging
import math
import mimetypes
import os
import posixpath
import re
import select
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from collections.abc import Mapping
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import PurePosixPath
from typing import Any
from urllib.parse import unquote

import anyio
import httpx
from mcp.server.mcpserver import MCPServer
from mcp.types import CallToolResult, ImageContent, TextContent, ToolAnnotations

LOGGER = logging.getLogger("synology_file_station_mcp")

MEDIA_EXTENSIONS = frozenset(
    {
        ".aac",
        ".avi",
        ".flac",
        ".m4a",
        ".mkv",
        ".mov",
        ".mp3",
        ".mp4",
        ".oga",
        ".ogg",
        ".opus",
        ".wav",
        ".webm",
    }
)
FORBIDDEN_MEDIA_EXTENSIONS = frozenset({".m3u", ".m3u8", ".pls", ".cue", ".concat"})


class AdapterError(Exception):
    """An error whose message is safe to return to an MCP caller."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class SessionExpired(AdapterError):
    """The Synology API rejected the in-memory SID."""

    def __init__(self):
        super().__init__("session_expired", "The File Station session expired.")


@dataclass(frozen=True)
class Limits:
    """Resource ceilings shared by every tool invocation."""

    page_size: int = 100
    text_bytes: int = 1 * 1024 * 1024
    document_bytes: int = 25 * 1024 * 1024
    image_bytes: int = 25 * 1024 * 1024
    media_probe_bytes: int = 64 * 1024 * 1024
    media_small_bytes: int = 8 * 1024 * 1024
    output_bytes: int = 2 * 1024 * 1024
    archive_members: int = 512
    archive_expanded_bytes: int = 100 * 1024 * 1024
    pdf_pages: int = 32
    image_pixels: int = 40_000_000
    temp_disk_bytes: int = 100 * 1024 * 1024
    parser_timeout_seconds: float = 15.0
    request_timeout_seconds: float = 20.0
    search_timeout_seconds: float = 20.0


def _env_int(name: str, default: int, minimum: int = 1) -> int:
    """Read a bounded integer override without revealing its value in errors."""

    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise AdapterError("configuration", f"{name} must be an integer.") from exc
    if value < minimum:
        raise AdapterError("configuration", f"{name} is below its minimum.")
    return value


def load_limits() -> Limits:
    """Load operator-adjustable ceilings with conservative defaults."""

    defaults = Limits()
    return Limits(
        page_size=_env_int("SYNOLOGY_PAGE_SIZE", defaults.page_size),
        text_bytes=_env_int("SYNOLOGY_TEXT_BYTES", defaults.text_bytes),
        document_bytes=_env_int("SYNOLOGY_DOCUMENT_BYTES", defaults.document_bytes),
        image_bytes=_env_int("SYNOLOGY_IMAGE_BYTES", defaults.image_bytes),
        media_probe_bytes=_env_int(
            "SYNOLOGY_MEDIA_PROBE_BYTES", defaults.media_probe_bytes
        ),
        media_small_bytes=_env_int(
            "SYNOLOGY_MEDIA_SMALL_BYTES", defaults.media_small_bytes
        ),
        output_bytes=_env_int("SYNOLOGY_OUTPUT_BYTES", defaults.output_bytes),
        archive_members=_env_int("SYNOLOGY_ARCHIVE_MEMBERS", defaults.archive_members),
        archive_expanded_bytes=_env_int(
            "SYNOLOGY_ARCHIVE_EXPANDED_BYTES", defaults.archive_expanded_bytes
        ),
        pdf_pages=_env_int("SYNOLOGY_PDF_PAGES", defaults.pdf_pages),
        image_pixels=_env_int("SYNOLOGY_IMAGE_PIXELS", defaults.image_pixels),
        temp_disk_bytes=_env_int("SYNOLOGY_TEMP_DISK_BYTES", defaults.temp_disk_bytes),
    )


def _safe_text(value: Any, limit: int = 400) -> str:
    """Keep user or upstream text out of logs and error payloads."""

    text = str(value).replace("\x00", " ").replace("\r", " ").replace("\n", " ")
    return text[:limit]


def _result_text(payload: Any, *, is_error: bool = False) -> CallToolResult:
    """Encode structured values as bounded JSON text for broad MCP clients."""

    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), default=str)
    if len(text.encode("utf-8")) > _env_int(
        "SYNOLOGY_OUTPUT_BYTES", Limits().output_bytes
    ):
        raise AdapterError(
            "output_limit", "The encoded tool response exceeds its limit."
        )
    return CallToolResult(
        content=[TextContent(type="text", text=text)], isError=is_error
    )


def _error_result(error: Exception) -> CallToolResult:
    """Return only a stable public error code and sanitized message."""

    if isinstance(error, AdapterError):
        return _result_text({"error": error.code, "message": str(error)}, is_error=True)
    # Do not log the exception object: HTTP clients and parser libraries can
    # include URLs, request bodies, local paths, or credentials in tracebacks.
    LOGGER.error("unexpected adapter failure code=internal_error")
    return _result_text(
        {"error": "internal_error", "message": "The request could not be completed."},
        is_error=True,
    )


def _decode_path(value: str) -> str:
    """Reject traversal before and after two URL-decoding passes."""

    if not isinstance(value, str) or not value or len(value) > 4096 or "\x00" in value:
        raise AdapterError("invalid_path", "The path is invalid.")
    candidate = value
    for _ in range(3):
        # Encoded separators are rejected even when a later parser would treat
        # them as ordinary text; this prevents double-encoded traversal.
        lowered = candidate.lower()
        if any(token in lowered for token in ("%2f", "%5c", "%00", "%2e")):
            raise AdapterError(
                "invalid_path", "Encoded path separators are not allowed."
            )
        decoded = unquote(candidate)
        if decoded == candidate:
            break
        candidate = decoded
    if "\\" in candidate or "\x00" in candidate or candidate.startswith("/"):
        raise AdapterError("invalid_path", "Only relative POSIX paths are allowed.")
    parts = candidate.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise AdapterError(
            "invalid_path", "Traversal and empty path segments are not allowed."
        )
    if "%" in candidate or any(ord(char) < 32 for char in candidate):
        raise AdapterError(
            "invalid_path",
            "The path contains unsupported escapes or control characters.",
        )
    normalized = posixpath.normpath(candidate)
    if normalized in {"", "."} or normalized.startswith("../") or normalized == "..":
        raise AdapterError("invalid_path", "The path escapes the configured share.")
    return normalized


def _join_remote(root: str, relative: str) -> str:
    """Join a validated relative path without allowing remote root escape."""

    if relative in {"", "."}:
        return root
    path = posixpath.join(root, relative)
    prefix = root.rstrip("/") + "/"
    if path != root and not path.startswith(prefix):
        raise AdapterError("invalid_path", "The path escapes the configured share.")
    return path


def _is_within_root(path: str, root: str) -> bool:
    """Check a File Station real_path with a segment-aware prefix."""

    if not _safe_remote_absolute(path) or not _safe_remote_absolute(root):
        return False
    normalized = posixpath.normpath(path)
    normalized_root = posixpath.normpath(root)
    return normalized == normalized_root or normalized.startswith(
        normalized_root.rstrip("/") + "/"
    )


def _safe_remote_absolute(path: str) -> bool:
    """Reject raw remote traversal before normalizing a returned path."""

    if (
        not isinstance(path, str)
        or "\x00" in path
        or "\\" in path
        or not path.startswith("/")
    ):
        return False
    parts = path.split("/")
    # File Station metadata is untrusted just like caller paths. Reject empty
    # interior segments, controls, and encoded forms before normalization so a
    # returned path cannot smuggle traversal into a relative result.
    if any(part == "" for part in parts[1:]):
        return False
    if any(
        part in {".", ".."} or any(ord(char) < 32 for char in part) for part in parts
    ):
        return False
    return all("%" not in part for part in parts)


def _relative_from_virtual(path: str, virtual_root: str) -> str:
    """Return a caller-visible path relative to the verified virtual share."""

    if not _safe_remote_absolute(path) or not _safe_remote_absolute(virtual_root):
        raise AdapterError(
            "outside_root", "The returned item is outside the configured share."
        )
    normalized = posixpath.normpath(path)
    root = posixpath.normpath(virtual_root)
    if normalized == root:
        return "."
    prefix = root.rstrip("/") + "/"
    if not normalized.startswith(prefix):
        raise AdapterError(
            "outside_root", "The returned item is outside the configured share."
        )
    return normalized[len(prefix) :]


def _mime_for(name: str) -> str:
    """Map a file name to a conservative content type."""

    return mimetypes.guess_type(name)[0] or "application/octet-stream"


def _extension(name: str) -> str:
    """Return a normalized extension including the leading dot."""

    suffix = PurePosixPath(name).suffix.lower()
    return suffix if len(suffix) <= 12 else ""


def _check_zip_limits(data: bytes, limits: Limits) -> None:
    """Inspect archives before parser extraction to cap expansion and paths."""

    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            if len(infos) > limits.archive_members:
                raise AdapterError(
                    "archive_limit", "The archive contains too many members."
                )
            expanded = 0
            for info in infos:
                name = info.filename.replace("\\", "/")
                if name.startswith("/") or any(
                    part in {"", ".", ".."} for part in name.split("/")
                ):
                    raise AdapterError(
                        "archive_path", "The archive contains an unsafe member path."
                    )
                expanded += max(0, info.file_size)
                if expanded > limits.archive_expanded_bytes:
                    raise AdapterError(
                        "archive_limit",
                        "The archive expands beyond the configured limit.",
                    )
    except zipfile.BadZipFile:
        # The converter will provide the format-specific error for non-archives.
        return


def _convert_document_local(data: bytes, name: str, limits: Limits) -> str:
    """Convert only the approved document formats inside an isolated worker."""

    if _extension(name) not in {".pdf", ".docx", ".xlsx", ".pptx"}:
        raise AdapterError(
            "document_type", "Only PDF, DOCX, XLSX and PPTX are supported."
        )
    extension = _extension(name)
    if extension == ".pdf":
        if not data.startswith(b"%PDF-"):
            raise AdapterError("document_parse", "The PDF signature is invalid.")
    else:
        if not zipfile.is_zipfile(io.BytesIO(data)):
            raise AdapterError(
                "document_parse", "The Office file is not a valid archive."
            )
        required = {
            ".docx": "word/document.xml",
            ".xlsx": "xl/workbook.xml",
            ".pptx": "ppt/presentation.xml",
        }[extension]
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if required not in archive.namelist() or any(
                info.flag_bits & 1 for info in archive.infolist()
            ):
                raise AdapterError(
                    "document_parse", "The Office archive is incomplete or encrypted."
                )
    _check_zip_limits(data, limits)
    from markitdown import MarkItDown

    if _extension(name) == ".pdf":
        import pypdfium2 as pdfium

        with pdfium.PdfDocument(data) as document:
            if len(document) > limits.pdf_pages:
                raise AdapterError("pdf_limit", "The PDF exceeds the page limit.")
    result = MarkItDown(enable_plugins=False).convert_stream(
        io.BytesIO(data), file_extension=_extension(name)
    )
    text = result.text_content
    if len(text.encode("utf-8")) > limits.output_bytes:
        raise AdapterError(
            "output_limit", "The converted document exceeds the response limit."
        )
    return text


def _parse_worker(
    kind: str, data: bytes, name: str, limits: Limits, page: int = 1
) -> Any:
    """Bound parser lifetime/output and delete its private scratch on every exit."""

    if len(data) > min(
        limits.document_bytes if kind != "image" else limits.image_bytes,
        limits.temp_disk_bytes,
    ):
        raise AdapterError(
            "download_limit", "The parser source exceeds its configured limit."
        )
    with tempfile.TemporaryDirectory(prefix="mcp-parser-") as directory:
        from pathlib import Path

        source = Path(directory) / "source"
        source.write_bytes(data)
        config = Path(directory) / "config.json"
        config.write_text(
            json.dumps(
                {
                    "kind": kind,
                    "extension": _extension(name),
                    "page": page,
                    "limits": asdict(limits),
                }
            )
        )
        raw = _bounded_process_output(
            [
                sys.executable,
                "-m",
                "synology_file_station_mcp.worker",
                str(source),
                str(config),
            ],
            limits.parser_timeout_seconds,
            (limits.output_bytes * 4 // 3) + 4096,
            {
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "LC_ALL": "C",
                "HOME": directory,
                "TMPDIR": directory,
                # Keep numerical parser libraries within the worker address
                # ceiling instead of creating one thread per host CPU.
                "OPENBLAS_NUM_THREADS": "1",
                "OMP_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
                "NUMEXPR_NUM_THREADS": "1",
            },
        )
        if raw is None:
            raise AdapterError(
                "parser_failed",
                "The parser failed, timed out or exceeded a resource limit.",
            )
        value = json.loads(raw)
        if "error" in value:
            raise AdapterError(
                "parser_rejected", "The parser rejected the file or a configured limit."
            )
        return value["result"]


def _convert_document(data: bytes, name: str, limits: Limits) -> str:
    """Keep MarkItDown outside the credential-bearing MCP process."""
    return _parse_worker("document", data, name, limits)


def _image_content(data: bytes, limits: Limits) -> ImageContent:
    """Return a bounded native image from an isolated decoder."""
    return ImageContent.model_validate(
        _parse_worker("image", data, "image.png", limits)
    )


def _pdf_page(data: bytes, page: int, limits: Limits) -> ImageContent:
    """Render a scanned page in a worker with no credentials or network access."""
    return ImageContent.model_validate(
        _parse_worker("pdf", data, "document.pdf", limits, page)
    )


def _image_content_local(data: bytes, limits: Limits) -> ImageContent:
    """Decode an image and return a native MCP image payload."""

    try:
        from PIL import Image

        with Image.open(io.BytesIO(data)) as source:
            width, height = source.size
            if width <= 0 or height <= 0 or width * height > limits.image_pixels:
                raise AdapterError("image_limit", "The image exceeds the pixel limit.")
            image = source.convert("RGB")
            output = io.BytesIO()
            image.save(output, format="PNG", optimize=True)
    except AdapterError:
        raise
    except Exception as exc:
        LOGGER.warning("image preview failed: %s", type(exc).__name__)
        raise AdapterError("image_parse", "The image could not be decoded.") from exc
    if output.tell() > limits.output_bytes:
        raise AdapterError("output_limit", "The image exceeds the response limit.")
    encoded = base64.b64encode(output.getvalue()).decode("ascii")
    return ImageContent(type="image", data=encoded, mimeType="image/png")


def _pdf_page_local(data: bytes, page: int, limits: Limits) -> ImageContent:
    """Render one PDF page for scanned documents without extracting a full PDF."""

    if page < 1:
        raise AdapterError("invalid_page", "The page number must be positive.")
    try:
        import pypdfium2 as pdfium

        document = pdfium.PdfDocument(data)
        try:
            count = len(document)
            if count > limits.pdf_pages:
                raise AdapterError(
                    "pdf_limit", "The PDF has too many pages for preview."
                )
            if page > count:
                raise AdapterError("invalid_page", "The requested page does not exist.")
            pdf_page = document.get_page(page - 1)
            try:
                width, height = pdf_page.get_size()
                if (
                    width <= 0
                    or height <= 0
                    or math.ceil(width * 1.5) * math.ceil(height * 1.5)
                    > limits.image_pixels
                ):
                    raise AdapterError(
                        "image_limit", "The page exceeds the pixel limit."
                    )
                bitmap = pdf_page.render(scale=1.5)
                try:
                    rendered = bitmap.to_pil().copy()
                finally:
                    bitmap.close()
            finally:
                # PdfPage is not a context manager in every supported pypdfium2
                # release, so close it explicitly even when rendering fails.
                pdf_page.close()
        finally:
            document.close()
        if rendered.width * rendered.height > limits.image_pixels:
            raise AdapterError(
                "image_limit", "The rendered page exceeds the pixel limit."
            )
        output = io.BytesIO()
        rendered.save(output, format="PNG", optimize=True)
    except AdapterError:
        raise
    except Exception as exc:
        LOGGER.warning("PDF preview failed: %s", type(exc).__name__)
        raise AdapterError("pdf_parse", "The PDF page could not be rendered.") from exc
    if output.tell() > limits.output_bytes:
        raise AdapterError(
            "output_limit", "The rendered page exceeds the response limit."
        )
    return ImageContent(
        type="image",
        data=base64.b64encode(output.getvalue()).decode("ascii"),
        mimeType="image/png",
    )


FFPROBE_FORMATS = "aac,avi,flac,matroska,mov,mp3,mpegts,ogg,wav"
FFPROBE_PROTOCOLS = "file,http,tcp"
FFPROBE_OUTPUT_BYTES = 256 * 1024


def _bounded_process_output(
    command: list[str], timeout: float, limit: int, env: Mapping[str, str]
) -> bytes | None:
    """Run a parser with a hard output cap before bytes enter this process."""

    process: subprocess.Popen[bytes] | None = None
    output = bytearray()
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            env=dict(env),
            close_fds=True,
        )
        if process.stdout is None:
            return None
        file_descriptor = process.stdout.fileno()
        os.set_blocking(file_descriptor, False)
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            readable, _, _ = select.select(
                [file_descriptor], [], [], min(remaining, 0.25)
            )
            if readable:
                chunk = os.read(
                    file_descriptor, min(64 * 1024, limit - len(output) + 1)
                )
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > limit:
                    return None
            elif process.poll() is not None:
                # The child exited without more readable bytes.
                break
        if process.wait(timeout=max(0.1, min(1.0, deadline - time.monotonic()))) != 0:
            return None
        return bytes(output)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
            with contextlib.suppress(OSError, subprocess.TimeoutExpired):
                process.wait(timeout=1)
            if process.stdout is not None:
                process.stdout.close()


def _ffprobe(path: str, timeout: float = 5.0) -> Mapping[str, Any] | None:
    """Probe an adapter-owned file or loopback range URL with safe ffprobe flags."""

    # The child receives a minimal environment, never the deployment's
    # credentials or proxy settings. Format and protocol allowlists keep
    # crafted media from opening playlists, concat files, or external URLs.
    safe_env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "LC_ALL": "C"}
    command = [
        "ffprobe",
        "-v",
        "error",
        "-protocol_whitelist",
        "http,tcp" if path.startswith("http://127.0.0.1:") else "file",
        "-format_whitelist",
        FFPROBE_FORMATS,
        "-show_entries",
        "format=format_name,duration,bit_rate,probe_score:stream=codec_name,codec_type,width,height,r_frame_rate,avg_frame_rate,sample_rate,channels,channel_layout,language,bit_rate,duration,profile",
        "-probesize",
        "1048576",
        "-analyzeduration",
        "2000000",
        "-rw_timeout",
        "3000000",
        "-of",
        "json",
        path,
    ]
    raw = _bounded_process_output(command, timeout, FFPROBE_OUTPUT_BYTES, safe_env)
    if raw is None:
        return None
    try:
        value = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict):
        return None
    # Keep output payload-free and stable; raw tags can contain credentials or
    # attacker-controlled paths and are not useful to callers.
    allowed_format = {"format_name", "duration", "bit_rate", "probe_score"}
    allowed_stream = {
        "codec_name",
        "codec_type",
        "width",
        "height",
        "r_frame_rate",
        "avg_frame_rate",
        "sample_rate",
        "channels",
        "channel_layout",
        "language",
        "bit_rate",
        "duration",
        "profile",
    }
    result: dict[str, Any] = {}
    if isinstance(value.get("format"), Mapping):
        result["format"] = {
            key: value["format"][key]
            for key in allowed_format
            if key in value["format"]
        }
    if isinstance(value.get("streams"), list):
        result["streams"] = [
            {key: stream[key] for key in allowed_stream if key in stream}
            for stream in value["streams"]
            if isinstance(stream, Mapping)
        ][:16]
    return result


class _RangeFacade:
    """Serve authenticated NAS byte ranges through one ephemeral loopback URL."""

    def __init__(self, client: FileStationClient, remote_path: str, size: int):
        self.client = client
        self.remote_path = remote_path
        self.size = size
        self.limit = client.limits.media_probe_bytes
        self.used = 0
        self.lock = threading.Lock()
        self.server: ThreadingHTTPServer | None = None
        self.thread: threading.Thread | None = None
        import secrets

        self.resource = "/" + secrets.token_hex(24)
        self.failure: str | None = None
        self.closed = threading.Event()
        self.active_handlers: set[threading.Thread] = set()

    def __enter__(self) -> str:
        owner = self

        class Handler(BaseHTTPRequestHandler):
            """Translate local Range requests to authenticated File Station calls."""

            server_version = "mcp-range-facade"
            sys_version = ""

            def do_HEAD(self) -> None:
                if self.path.split("?", 1)[0] != owner.resource:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(owner.size))
                self.end_headers()

            def do_GET(self) -> None:
                current = threading.current_thread()
                with owner.lock:
                    owner.active_handlers.add(current)
                try:
                    self._do_get()
                finally:
                    with owner.lock:
                        owner.active_handlers.discard(current)

            def _do_get(self) -> None:
                if owner.closed.is_set():
                    self._range_error()
                    return
                if self.path.split("?", 1)[0] != owner.resource:
                    self.send_error(404)
                    return
                range_header = self.headers.get("Range", "")
                match = re.fullmatch(r"bytes=(\d+)-(\d*)", range_header)
                suffix = re.fullmatch(r"bytes=-(\d+)", range_header)
                if suffix:
                    requested = min(int(suffix.group(1)), owner.size)
                    start, end = owner.size - requested, owner.size - 1
                elif match:
                    start = int(match.group(1))
                    end = int(match.group(2)) if match.group(2) else owner.size - 1
                else:
                    self._range_error()
                    return
                if start < 0 or end < start or start >= owner.size:
                    self._range_error()
                    return
                end = min(end, owner.size - 1)
                # Open-ended ffprobe reads are translated into bounded blocks;
                # it can reconnect or seek without downloading the whole file.
                end = min(end, start + 256 * 1024 - 1)
                length = end - start + 1
                with owner.lock:
                    if owner.used + length > owner.limit:
                        owner.failure = (
                            "The cumulative media transfer budget was exhausted."
                        )
                        self._range_error()
                        return
                    try:
                        data, response = owner.client._download(
                            owner.remote_path,
                            limit=length,
                            range_header=f"bytes={start}-{end}",
                            expected_size=owner.size,
                            on_bytes=owner._count_bytes,
                        )
                    except AdapterError:
                        owner.failure = "The NAS range response was unavailable or failed verification."
                        self.send_error(502)
                        return
                    if not owner.client._valid_range_response(
                        response, data, owner.size, start, end
                    ):
                        self.send_error(502)
                        return
                self.send_response(206)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", f"bytes {start}-{end}/{owner.size}")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Content-Type", "application/octet-stream")
                self.end_headers()
                with contextlib.suppress(BrokenPipeError, ConnectionResetError):
                    self.wfile.write(data)

            def _range_error(self) -> None:
                self.send_response(416)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", f"bytes */{owner.size}")
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, _format: str, *_args: Any) -> None:
                # Request URLs can contain media names; keep them out of logs.
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = False
        self.server.block_on_close = True
        self.thread = threading.Thread(
            target=self.server.serve_forever, name="mcp-range-facade", daemon=True
        )
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}{self.resource}"

    def __exit__(self, _exc_type: object, _exc: object, _tb: object) -> None:
        # Stop new requests first, then wait for handlers that may still hold
        # an authenticated stream. The event also makes a late body chunk
        # fail closed instead of continuing a transfer after ffprobe returns.
        self.closed.set()
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
        if self.thread is not None:
            self.thread.join(timeout=2)
        with self.lock:
            active = tuple(self.active_handlers)
        for handler in active:
            handler.join(timeout=2)

    def _count_bytes(self, count: int) -> None:
        """Account for partial transfers and abort work after facade close."""

        if self.closed.is_set():
            raise AdapterError("range_cancelled", "The media inspection was cancelled.")
        self.used += count


class FileStationClient:
    """HTTPS client constrained to one File Station share and one origin."""

    def __init__(
        self,
        *,
        origin: str | None = None,
        username: str | None = None,
        password: str | None = None,
        http_client: httpx.Client | None = None,
        limits: Limits | None = None,
    ):
        self.origin = origin or os.getenv(
            "SYNOLOGY_ORIGIN", "https://nas.bohdal.name:5001"
        ).rstrip("/")
        parsed = httpx.URL(self.origin)
        if (
            parsed.scheme != "https"
            or parsed.host != "nas.bohdal.name"
            or parsed.port != 5001
            or parsed.path not in {"", "/"}
        ):
            raise AdapterError(
                "configuration",
                "SYNOLOGY_ORIGIN must be the configured HTTPS NAS origin.",
            )
        self.username = (
            username if username is not None else os.getenv("SYNOLOGY_USERNAME", "")
        )
        self.password = (
            password if password is not None else os.getenv("SYNOLOGY_PASSWORD", "")
        )
        if not self.username or not self.password:
            raise AdapterError(
                "configuration", "Synology credentials are not configured."
            )
        self.limits = limits or load_limits()
        self._client = http_client or httpx.Client(
            base_url=self.origin,
            follow_redirects=False,
            trust_env=False,
            verify=True,
            timeout=self.limits.request_timeout_seconds,
        )
        self._sid: str | None = None
        self._virtual_root: str | None = None
        self._real_root = "/volume1/Media"
        if os.getenv("SYNOLOGY_REAL_ROOT", self._real_root) != self._real_root:
            raise AdapterError(
                "configuration", "The allowed real root is /volume1/Media."
            )

    def close(self) -> None:
        """Close the HTTP connection pool without persisting session state."""

        self._client.close()

    def _login(self) -> None:
        """Create a File Station SID in memory only."""

        try:
            # Authentication is a POST form too. Stream and cap its response
            # before parsing so an unexpected NAS body cannot consume memory.
            with self._client.stream(
                "POST",
                "/webapi/auth.cgi",
                data={
                    "api": "SYNO.API.Auth",
                    "version": "7",
                    "method": "login",
                    "account": self.username,
                    "passwd": self.password,
                    "session": "FileStation",
                    "format": "sid",
                },
            ) as response:
                self._check_http(response)
                if response.headers.get("content-encoding", "identity") != "identity":
                    raise AdapterError(
                        "authentication_failed", "Synology authentication failed."
                    )
                chunks = bytearray()
                deadline = time.monotonic() + self.limits.request_timeout_seconds
                for chunk in response.iter_bytes(chunk_size=16384):
                    chunks.extend(chunk)
                    if len(chunks) > 64 * 1024 or time.monotonic() > deadline:
                        raise AdapterError(
                            "authentication_failed", "Synology authentication failed."
                        )
                body = json.loads(chunks)
            sid = body.get("data", {}).get("sid") if body.get("success") else None
            if not isinstance(sid, str) or not sid:
                raise AdapterError(
                    "authentication_failed", "Synology authentication failed."
                )
        except AdapterError:
            raise
        except Exception as exc:
            LOGGER.warning("Synology authentication failed: %s", type(exc).__name__)
            raise AdapterError(
                "authentication_failed", "Synology authentication failed."
            ) from exc
        self._sid = sid

    @staticmethod
    def _check_http(response: httpx.Response) -> None:
        """Reject redirects and upstream bodies before callers inspect them."""

        if 300 <= response.status_code < 400:
            raise AdapterError("redirect_rejected", "Redirects are not allowed.")
        if response.status_code >= 400:
            raise AdapterError("upstream_http", "Synology returned an HTTP error.")

    def _request_json(
        self, params: Mapping[str, Any], *, retry: bool = True
    ) -> Mapping[str, Any]:
        """Bound API responses and keep SIDs out of request URLs."""
        if self._sid is None:
            self._login()
        query = dict(params)
        query["_sid"] = self._sid
        try:
            with self._client.stream(
                "POST", "/webapi/entry.cgi", data=query
            ) as response:
                self._check_http(response)
                chunks = bytearray()
                deadline = time.monotonic() + self.limits.request_timeout_seconds
                for chunk in response.iter_bytes(chunk_size=16384):
                    chunks.extend(chunk)
                    if len(chunks) > 1024 * 1024 or time.monotonic() > deadline:
                        raise AdapterError(
                            "api_limit", "The NAS metadata response exceeded a limit."
                        )
                body = json.loads(chunks)
            if not isinstance(body, Mapping):
                raise TypeError("Invalid response shape")
        except AdapterError:
            raise
        except Exception as exc:
            raise AdapterError(
                "upstream_unavailable", "Synology could not complete the request."
            ) from exc
        if body.get("success") is True:
            return body.get("data") if isinstance(body.get("data"), Mapping) else {}
        code = body.get("error", {}).get("code")
        if code in {105, 106, 107, 119} and retry:
            self._sid = None
            return self._request_json(params, retry=False)
        if code in {105, 106, 107, 119}:
            raise SessionExpired()
        raise AdapterError("upstream_rejected", "Synology rejected the request.")

    def _download(
        self,
        remote_path: str,
        *,
        limit: int,
        range_header: str | None = None,
        expected_size: int | None = None,
        on_bytes: Any = None,
    ) -> tuple[bytes, httpx.Response]:
        """Download bounded bytes from File Station and reject redirects."""

        if self._sid is None:
            self._login()
        headers = {"Range": range_header} if range_header else None
        query = {
            "api": "SYNO.FileStation.Download",
            "version": "2",
            "method": "download",
            # File Station documents path as a JSON array; this avoids commas
            # in a filename being interpreted as multiple download paths.
            "path": json.dumps([remote_path], separators=(",", ":")),
            "mode": "open",
            "_sid": self._sid,
        }
        try:
            with self._client.stream(
                "GET", "/webapi/entry.cgi", params=query, headers=headers
            ) as response:
                self._check_http(response)
                if response.headers.get("content-encoding", "identity") != "identity":
                    raise AdapterError(
                        "download_encoding", "Encoded downloads are not accepted."
                    )
                if range_header:
                    requested = re.fullmatch(r"bytes=(\d+)-(\d+)", range_header)
                    content_range = response.headers.get("content-range", "")
                    expected = (
                        f"bytes {requested.group(1)}-{requested.group(2)}/{expected_size}"
                        if requested
                        else ""
                    )
                    if (
                        response.status_code != 206
                        or content_range != expected
                        or response.headers.get("content-length") != str(limit)
                    ):
                        raise AdapterError(
                            "range_unverified",
                            "The NAS did not return a verified byte range.",
                        )
                announced = response.headers.get("content-length")
                if announced and announced.isdigit() and int(announced) > limit:
                    raise AdapterError(
                        "download_limit", "The download exceeds the configured limit."
                    )
                chunks: list[bytes] = []
                size = 0
                deadline = time.monotonic() + self.limits.request_timeout_seconds
                for chunk in response.iter_bytes(chunk_size=min(16384, max(1, limit))):
                    size += len(chunk)
                    if on_bytes:
                        on_bytes(len(chunk))
                    if time.monotonic() > deadline:
                        raise AdapterError(
                            "download_timeout", "The download exceeded its time limit."
                        )
                    if size > limit:
                        raise AdapterError(
                            "download_limit",
                            "The download exceeds the configured limit.",
                        )
                    chunks.append(chunk)
                    if range_header and size == limit:
                        break
                return b"".join(chunks), response
        except AdapterError:
            raise
        except Exception as exc:
            LOGGER.warning("Synology download failed: %s", type(exc).__name__)
            raise AdapterError(
                "download_failed", "Synology could not download the item."
            ) from exc

    def verify_root(self) -> str:
        """Resolve a documented File Station share and verify its real_path.

        ``list_share`` returns ``data.shares[].additional.real_path``. A normal
        directory listing is deliberately not accepted as the share root.
        """

        if self._virtual_root:
            return self._virtual_root
        data = self._request_json(
            {
                "api": "SYNO.FileStation.List",
                "version": "2",
                "method": "list_share",
                "additional": json.dumps(
                    ["real_path", "perm", "mount_point_type"], separators=(",", ":")
                ),
            }
        )
        entries = data.get("shares") or []
        desired_name = os.getenv("SYNOLOGY_SHARE_NAME", "Media")
        for item in entries:
            if not isinstance(item, Mapping):
                continue
            path = item.get("path")
            additional = (
                item.get("additional")
                if isinstance(item.get("additional"), Mapping)
                else {}
            )
            real_path = additional.get("real_path")
            name = item.get("name") or (
                posixpath.basename(str(path).rstrip("/")) if path else ""
            )
            if (
                name == desired_name
                and isinstance(path, str)
                and isinstance(real_path, str)
            ):
                if not _safe_remote_absolute(path) or not _safe_remote_absolute(
                    real_path
                ):
                    continue
                if posixpath.normpath(real_path) != posixpath.normpath(self._real_root):
                    continue
                mount_type = str(additional.get("mount_point_type", "")).lower()
                if "link" in mount_type or "symlink" in mount_type:
                    continue
                self._virtual_root = posixpath.normpath(path)
                return self._virtual_root
        raise AdapterError(
            "media_root_unverified",
            "The configured File Station share was not verified.",
        )

    def _remote_item(self, item: Mapping[str, Any]) -> dict[str, Any]:
        """Validate one upstream item and reduce it to safe relative metadata."""

        virtual_root = self.verify_root()
        remote_path = item.get("path")
        additional = (
            item.get("additional")
            if isinstance(item.get("additional"), Mapping)
            else {}
        )
        real_path = additional.get("real_path")
        if not isinstance(remote_path, str) or not isinstance(real_path, str):
            raise AdapterError(
                "upstream_schema", "Synology returned incomplete item metadata."
            )
        if not _is_within_root(real_path, self._real_root):
            raise AdapterError(
                "outside_root",
                "Synology returned an item outside the configured share.",
            )
        mount_type = str(additional.get("mount_point_type", "")).lower()
        if (
            "link" in mount_type
            or "symlink" in mount_type
            or item.get("is_symlink")
            or item.get("type") == "symlink"
        ):
            raise AdapterError("symlink_rejected", "Symlinks are not exposed.")
        relative = _relative_from_virtual(remote_path, virtual_root)
        if real_path != _join_remote(self._real_root, relative):
            raise AdapterError(
                "symlink_rejected", "Resolved links and remapped paths are not exposed."
            )
        return {
            "path": relative,
            "name": _safe_text(item.get("name", posixpath.basename(remote_path))),
            "is_dir": bool(item.get("isdir", item.get("is_dir", False))),
            "size": additional.get("size", item.get("size", item.get("filesize"))),
            "modified": additional.get("time", item.get("mtime", item.get("time"))),
            "mime_type": _mime_for(str(item.get("name", remote_path))),
        }

    def list_entries(self, path: str, page: int, page_size: int) -> dict[str, Any]:
        """List one bounded page of verified entries."""

        self._virtual_root = None
        relative = "." if path in {"", "."} else _decode_path(path)
        remote_path = _join_remote(self.verify_root(), relative)
        if relative != ".":
            folder_info = self.stat(relative)
            if not folder_info["is_dir"]:
                raise AdapterError("not_a_directory", "The path is not a directory.")
        page_size = max(1, min(page_size, self.limits.page_size))
        if page < 1:
            raise AdapterError("invalid_page", "The page number must be positive.")
        data = self._request_json(
            {
                "api": "SYNO.FileStation.List",
                "version": "2",
                "method": "list",
                "folder_path": remote_path,
                "offset": (page - 1) * page_size,
                "limit": page_size,
                "sort_by": "name",
                "sort_direction": "asc",
                "additional": json.dumps(
                    ["real_path", "size", "time", "perm", "type", "mount_point_type"],
                    separators=(",", ":"),
                ),
            }
        )
        files = data.get("files") or data.get("items") or []
        if not isinstance(files, list):
            raise AdapterError(
                "upstream_schema", "Synology returned an invalid directory listing."
            )
        return {
            "path": relative,
            "page": page,
            "page_size": page_size,
            "items": [
                self._remote_item(item)
                for item in files[:page_size]
                if isinstance(item, Mapping)
            ],
            "is_truncated": bool(
                data.get("total") and (page * page_size) < int(data["total"])
            ),
        }

    def stat(self, path: str) -> dict[str, Any]:
        """Return verified metadata for one entry without downloading it."""

        self._virtual_root = None
        relative = "." if path in {"", "."} else _decode_path(path)
        remote_path = _join_remote(self.verify_root(), relative)
        data = self._request_json(
            {
                "api": "SYNO.FileStation.List",
                "version": "2",
                "method": "getinfo",
                "path": json.dumps([remote_path], separators=(",", ":")),
                "additional": json.dumps(
                    ["real_path", "size", "time", "perm", "type", "mount_point_type"],
                    separators=(",", ":"),
                ),
            }
        )
        files = data.get("files") or []
        if len(files) != 1 or not isinstance(files[0], Mapping):
            raise AdapterError(
                "upstream_schema", "Synology returned invalid item metadata."
            )
        item = dict(files[0])
        item_path = item.get("path")
        if not isinstance(item_path, str) or posixpath.normpath(
            item_path
        ) != posixpath.normpath(remote_path):
            raise AdapterError(
                "upstream_schema", "Synology returned metadata for an unexpected item."
            )
        item.setdefault("name", posixpath.basename(remote_path))
        return self._remote_item(item)

    def search(
        self, path: str, pattern: str, page_size: int, page: int = 1
    ) -> dict[str, Any]:
        """Run an asynchronous File Station search and always clean its task."""

        self._virtual_root = None
        relative = "." if path in {"", "."} else _decode_path(path)
        if page_size < 1 or page < 1:
            raise AdapterError(
                "invalid_page", "The page and page size must be positive."
            )
        if (
            not pattern
            or len(pattern) > 128
            or any(char in pattern for char in ("\x00", "\r", "\n"))
        ):
            raise AdapterError("invalid_pattern", "The search pattern is invalid.")
        folder = _join_remote(self.verify_root(), relative)
        if relative != ".":
            folder_info = self.stat(relative)
            if not folder_info["is_dir"]:
                raise AdapterError(
                    "not_a_directory", "The search path is not a directory."
                )
        task_id: str | None = None
        deadline = time.monotonic() + self.limits.search_timeout_seconds
        try:
            started = self._request_json(
                {
                    "api": "SYNO.FileStation.Search",
                    "version": "2",
                    "method": "start",
                    "folder_path": folder,
                    "pattern": pattern,
                    "recursive": "true",
                    "additional": json.dumps(
                        [
                            "real_path",
                            "size",
                            "time",
                            "perm",
                            "type",
                            "mount_point_type",
                        ],
                        separators=(",", ":"),
                    ),
                }
            )
            task_id = started.get("taskid") or started.get("task_id")
            if not isinstance(task_id, str) or not task_id:
                raise AdapterError(
                    "search_failed", "Synology did not return a search task."
                )
            while time.monotonic() < deadline:
                status = self._request_json(
                    {
                        "api": "SYNO.FileStation.Search",
                        "version": "2",
                        "method": "list",
                        "taskid": task_id,
                        "offset": (page - 1) * min(page_size, self.limits.page_size),
                        "limit": min(page_size, self.limits.page_size),
                        "additional": json.dumps(
                            [
                                "real_path",
                                "size",
                                "time",
                                "perm",
                                "type",
                                "mount_point_type",
                            ],
                            separators=(",", ":"),
                        ),
                    }
                )
                if status.get("finished", status.get("is_finished", False)):
                    files = status.get("files") or status.get("items") or []
                    return {
                        "path": relative,
                        "pattern": pattern,
                        "page": page,
                        "page_size": min(page_size, self.limits.page_size),
                        "items": [
                            self._remote_item(item)
                            for item in files[: min(page_size, self.limits.page_size)]
                            if isinstance(item, Mapping)
                        ],
                        "is_truncated": bool(
                            status.get("total")
                            and (page * min(page_size, self.limits.page_size))
                            < int(status["total"])
                        ),
                    }
                time.sleep(0.05)
            raise AdapterError("search_timeout", "The Synology search timed out.")
        finally:
            if task_id:
                for method in ("stop", "clean"):
                    try:
                        self._request_json(
                            {
                                "api": "SYNO.FileStation.Search",
                                "version": "2",
                                "method": method,
                                "taskid": task_id,
                            },
                            retry=False,
                        )
                    except Exception:  # noqa: BLE001 -- cleanup errors must never disclose NAS responses.
                        LOGGER.warning("search cleanup failed: %s", method)

    def read_bytes(self, path: str, limit: int) -> tuple[bytes, str]:
        """Verify an item then download it with a strict byte ceiling."""

        metadata = self.stat(path)
        if metadata.get("is_dir"):
            raise AdapterError("not_a_file", "Directories cannot be downloaded.")
        if metadata.get("size") is not None and int(metadata["size"]) > limit:
            raise AdapterError(
                "download_limit", "The file exceeds the configured limit."
            )
        relative = metadata["path"]
        remote_path = _join_remote(self.verify_root(), relative)
        data, _ = self._download(remote_path, limit=limit)
        return data, str(metadata.get("name") or posixpath.basename(relative))

    def media_info(self, path: str) -> dict[str, Any]:
        """Return basic metadata and optional bounded ffprobe details."""

        metadata = self.stat(path)
        size = metadata.get("size")
        try:
            size_int = int(size) if size is not None else None
        except (TypeError, ValueError):
            size_int = None
        result: dict[str, Any] = {**metadata, "inspection_limited": False}
        if size_int is None or size_int < 1:
            result["inspection_limited"] = True
            result["limitation"] = "Synology did not provide a file size."
            return result
        remote_path = _join_remote(self.verify_root(), str(metadata["path"]))
        extension = _extension(str(metadata.get("name", "")))
        if extension in FORBIDDEN_MEDIA_EXTENSIONS or extension not in MEDIA_EXTENSIONS:
            result["inspection_limited"] = True
            result["limitation"] = (
                "The media type is not in the local ffprobe allowlist."
            )
            return result
        if size_int <= min(
            self.limits.media_small_bytes, self.limits.media_probe_bytes
        ):
            data, _ = self._download(
                remote_path,
                limit=min(self.limits.media_small_bytes, self.limits.media_probe_bytes),
            )
            if not data:
                result["inspection_limited"] = True
                result["limitation"] = "The media download returned no bytes."
                return result
            with tempfile.NamedTemporaryFile(
                prefix="synology-mcp-",
                suffix=_extension(str(metadata.get("name", ""))),
                delete=True,
            ) as temporary:
                temporary.write(data)
                temporary.flush()
                probed = _ffprobe(temporary.name)
        else:
            # ffprobe seeks to the tail for containers whose metadata is stored
            # after the media payload. The facade translates every seek into a
            # verified NAS range request and enforces one cumulative budget.
            facade = _RangeFacade(self, remote_path, size_int)
            with facade as probe_url:
                probed = _ffprobe(probe_url)
            result["transferred_bytes"] = facade.used
            if facade.failure:
                result["inspection_limited"] = True
                result["limitation"] = facade.failure
        if probed is None:
            result["inspection_limited"] = True
            result.setdefault(
                "limitation", "ffprobe could not inspect the bounded media ranges."
            )
        else:
            result["ffprobe"] = probed
        return result

    @staticmethod
    def _valid_range_response(
        response: httpx.Response, data: bytes, size: int, start: int, end: int
    ) -> bool:
        """Require a self-consistent 206 response before parser bytes are used."""

        content_range = response.headers.get("content-range", "")
        match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", content_range)
        if response.status_code != 206 or not match:
            return False
        returned_start, returned_end, total = (
            int(match.group(index)) for index in (1, 2, 3)
        )
        announced = response.headers.get("content-length")
        if announced and announced.isdigit() and int(announced) != len(data):
            return False
        return (
            returned_start == start
            and returned_end == end
            and total == size
            and len(data) == end - start + 1
        )


class Adapter:
    """MCP-facing orchestration around a single File Station client."""

    def __init__(self, client: FileStationClient):
        self.client = client
        self.limits = client.limits

    def list_entries(
        self, path: str = ".", page: int = 1, page_size: int = 100
    ) -> CallToolResult:
        try:
            return _result_text(self.client.list_entries(path, page, page_size))
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def search(
        self, path: str, pattern: str, page_size: int = 100, page: int = 1
    ) -> CallToolResult:
        try:
            return _result_text(self.client.search(path, pattern, page_size, page))
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def stat(self, path: str) -> CallToolResult:
        try:
            return _result_text(self.client.stat(path))
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def read_text(self, path: str) -> CallToolResult:
        try:
            data, name = self.client.read_bytes(path, self.limits.text_bytes)
            text = data.decode("utf-8")
            if len(text.encode("utf-8")) > self.limits.output_bytes:
                raise AdapterError(
                    "output_limit", "The text exceeds the response limit."
                )
            return _result_text({"path": path, "name": name, "text": text})
        except UnicodeDecodeError:
            return _error_result(
                AdapterError("text_encoding", "The file is not UTF-8 text.")
            )
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def read_document(self, path: str) -> CallToolResult:
        try:
            data, name = self.client.read_bytes(path, self.limits.document_bytes)
            text = _convert_document(data, name, self.limits)
            return _result_text({"path": path, "name": name, "markdown": text})
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def preview_image(self, path: str) -> CallToolResult:
        try:
            data, name = self.client.read_bytes(path, self.limits.image_bytes)
            image = _image_content(data, self.limits)
            return CallToolResult(
                content=[
                    TextContent(
                        type="text", text=json.dumps({"path": path, "name": name})
                    ),
                    image,
                ]
            )
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def preview_pdf_page(self, path: str, page: int = 1) -> CallToolResult:
        try:
            data, name = self.client.read_bytes(path, self.limits.document_bytes)
            image = _pdf_page(data, page, self.limits)
            return CallToolResult(
                content=[
                    TextContent(
                        type="text",
                        text=json.dumps({"path": path, "name": name, "page": page}),
                    ),
                    image,
                ]
            )
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)

    def media_info(self, path: str) -> CallToolResult:
        try:
            return _result_text(self.client.media_info(path))
        except Exception as exc:  # noqa: BLE001 -- sanitize upstream/parser failures at the MCP boundary.
            return _error_result(exc)


def create_adapter(client: FileStationClient | None = None) -> Adapter:
    """Build an adapter from environment configuration or a test client."""

    return Adapter(client or FileStationClient())


def build_server(adapter: Adapter | None = None) -> MCPServer:
    """Register exactly the eight approved read-only tools."""

    service = adapter or create_adapter()
    serial = asyncio.Lock()

    async def invoke(function: Any, *args: Any) -> CallToolResult:
        async with serial:
            return await anyio.to_thread.run_sync(
                functools.partial(function, *args), abandon_on_cancel=False
            )

    server = MCPServer(
        name="synology-file-station-mcp",
        version="0.1.0",
        description="Read-only, bounded access to the configured Synology Media share.",
        instructions="Only the configured Media share is exposed. Results are bounded and symlinks/traversal are rejected.",
    )

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="list_entries",
        description="List a bounded page of entries in the verified Media share.",
    )
    async def list_entries(
        path: str = ".", page: int = 1, page_size: int = 100
    ) -> CallToolResult:
        return await invoke(service.list_entries, path, page, page_size)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="search_by_name",
        description="Search by name in the verified Media share.",
    )
    async def search_by_name(
        path: str, pattern: str, page_size: int = 100, page: int = 1
    ) -> CallToolResult:
        return await invoke(service.search, path, pattern, page_size, page)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="stat",
        description="Return verified metadata for one Media entry.",
    )
    async def stat(path: str) -> CallToolResult:
        return await invoke(service.stat, path)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="read_text",
        description="Read a bounded UTF-8 text file from Media.",
    )
    async def read_text(path: str) -> CallToolResult:
        return await invoke(service.read_text, path)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="read_document",
        description="Convert a bounded PDF, DOCX, XLSX, or PPTX file to Markdown.",
    )
    async def read_document(path: str) -> CallToolResult:
        return await invoke(service.read_document, path)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="preview_image",
        description="Return an image as a native MCP image payload.",
    )
    async def preview_image(path: str) -> CallToolResult:
        return await invoke(service.preview_image, path)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="preview_pdf_page",
        description="Render one bounded PDF page as a native MCP image payload.",
    )
    async def preview_pdf_page(path: str, page: int = 1) -> CallToolResult:
        return await invoke(service.preview_pdf_page, path, page)

    @server.tool(
        annotations=ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        ),
        name="media_info",
        description="Return metadata and bounded ffprobe details for media files.",
    )
    async def media_info(path: str) -> CallToolResult:
        return await invoke(service.media_info, path)

    return server


def main() -> None:
    """Run one stdio MCP server; tunnel-client owns the parent process."""

    logging.basicConfig(level=logging.ERROR)
    logging.getLogger("httpx").disabled = True
    logging.getLogger("httpcore").disabled = True
    adapter = create_adapter()
    try:
        server = build_server(adapter)
        asyncio.run(server.run_stdio_async())
    finally:
        adapter.client.close()


if __name__ == "__main__":
    main()
