"""Exercise real adapter boundaries with official-shaped, credential-free NAS fixtures."""

from __future__ import annotations

import io
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs

import httpx
from PIL import Image
from synology_file_station_mcp.server import (
    Adapter,
    AdapterError,
    FileStationClient,
    Limits,
    _bounded_process_output,
    _convert_document,
    _ffprobe,
    _image_content,
    _pdf_page,
    _RangeFacade,
    _result_text,
)
from test_server import _minimal_pdf, _pptx_fixture, _xlsx_fixture, _zip_fixture


class FixtureNAS:
    """Serve only the documented API methods and count every downloaded byte."""

    def __init__(self, payload=b"fixture text", name="fixture.txt", limits=None):
        self.payload, self.name = payload, name
        self.size = len(payload)
        self.ranges, self.calls = [], []
        self.range_mode = "valid"
        self.real_path = "/volume1/Media/" + name
        self.returned_path = "/Media/" + name
        self.expired = False
        self.login_count = 0
        self.client = FileStationClient(
            username="fixture-user",
            password="fixture-password",
            limits=limits or Limits(),
            http_client=httpx.Client(
                base_url="https://nas.bohdal.name:5001",
                transport=httpx.MockTransport(self.handle),
                follow_redirects=False,
                trust_env=False,
            ),
        )

    def handle(self, request):
        """Authentication is POST; downloads have an exact single-path array."""
        params = (
            parse_qs(request.content.decode())
            if request.method == "POST"
            else dict(request.url.params.multi_items())
        )
        params = {
            key: value[0] if isinstance(value, list) else value
            for key, value in params.items()
        }
        method = params.get("method")
        self.calls.append(method)
        if method == "login":
            assert request.method == "POST" and not request.url.query
            self.login_count += 1
            return httpx.Response(
                200, json={"success": True, "data": {"sid": "fixture-sid"}}
            )
        if self.expired:
            self.expired = False
            return httpx.Response(200, json={"success": False, "error": {"code": 106}})
        if method == "list_share":
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "data": {
                        "shares": [
                            {
                                "name": "Media",
                                "path": "/Media",
                                "additional": {"real_path": "/volume1/Media"},
                            }
                        ]
                    },
                },
            )
        if method == "getinfo":
            assert json.loads(params["path"]) == ["/Media/" + self.name]
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "data": {
                        "files": [
                            {
                                "name": self.name,
                                "path": self.returned_path,
                                "isdir": False,
                                "additional": {
                                    "real_path": self.real_path,
                                    "size": self.size,
                                },
                            }
                        ]
                    },
                },
            )
        if method == "download":
            assert json.loads(params["path"]) == ["/Media/" + self.name]
            raw_range = request.headers.get("range")
            if not raw_range:
                return httpx.Response(
                    200,
                    content=self.payload,
                    headers={"content-length": str(len(self.payload))},
                )
            start, end = map(int, raw_range.removeprefix("bytes=").split("-"))
            self.ranges.append((start, end))
            data = self.read_range(start, end)
            headers = {
                "content-range": f"bytes {start}-{end}/{self.size}",
                "content-length": str(len(data)),
            }
            status = 206
            if self.range_mode == "ignored":
                status = 200
            if self.range_mode == "mismatch":
                headers["content-range"] = f"bytes {start + 1}-{end}/{self.size}"
            if self.range_mode == "truncated":
                data = data[:-1]
            return httpx.Response(status, content=data, headers=headers)
        raise AssertionError("Unexpected fixture API method")

    def read_range(self, start, end):
        """Return a regular range; large sparse media override this method."""
        return self.payload[start : end + 1]

    def close(self):
        """Close fixture resources after each assertion, including failure paths."""
        self.client.close()


class BoundaryTests(unittest.TestCase):
    """Check data, path, authentication and bounded-failure behavior."""

    def test_text_and_missing_size(self):
        nas = FixtureNAS()
        try:
            result = Adapter(nas.client).read_text(nas.name)
            self.assertFalse(result.is_error)
            self.assertEqual(json.loads(result.content[0].text)["text"], "fixture text")
            nas.size = None
            result = nas.client.media_info(nas.name)
            self.assertTrue(result["inspection_limited"])
        finally:
            nas.close()

    def test_returned_escape_link_and_wrong_item_are_rejected(self):
        for remote, real in (
            ("/Other/fixture.txt", "/volume1/Media/fixture.txt"),
            ("/Media/../Other/fixture.txt", "/volume1/Media/fixture.txt"),
            ("/Media/%2e%2e/fixture.txt", "/volume1/Media/fixture.txt"),
            ("/Media/fixture.txt", "/volume1/Other/fixture.txt"),
            ("/Media/fixture.txt", "/volume1/Media/linked-target.txt"),
            ("/Media/another.txt", "/volume1/Media/another.txt"),
        ):
            with self.subTest(remote=remote, real=real):
                nas = FixtureNAS()
                nas.returned_path, nas.real_path = remote, real
                try:
                    self.assertTrue(Adapter(nas.client).read_text(nas.name).is_error)
                    self.assertNotIn("download", nas.calls)
                finally:
                    nas.close()

    def test_expired_auth_retries_once(self):
        nas = FixtureNAS()
        nas.expired = True
        try:
            self.assertEqual(nas.client.stat(nas.name)["path"], nas.name)
            self.assertEqual(nas.login_count, 2)
        finally:
            nas.close()

    def test_outage_and_limits_are_payload_free(self):
        nas = FixtureNAS(payload=b"secret file content", limits=Limits(text_bytes=3))
        try:
            result = Adapter(nas.client).read_text(nas.name)
            self.assertTrue(result.is_error)
            self.assertNotIn("secret file content", result.content[0].text)
            self.assertNotIn("download", nas.calls)
            with patch.object(
                nas.client,
                "_request_json",
                side_effect=httpx.ConnectError("password=fixture-password"),
            ):
                result = Adapter(nas.client).stat(nas.name)
                self.assertNotIn("fixture-password", result.content[0].text)
        finally:
            nas.close()

    def test_encoded_response_limit(self):
        with self.assertRaises(AdapterError):
            _result_text({"text": "\x00" * (1024 * 1024)})

    def test_native_image_and_parser_cleanup_after_failure(self):
        image = Image.new("RGB", (4, 3), "blue")
        data = io.BytesIO()
        image.save(data, format="PNG")
        nas = FixtureNAS(data.getvalue(), "image.png")
        try:
            result = Adapter(nas.client).preview_image(nas.name)
            self.assertFalse(result.is_error)
            self.assertEqual(result.content[1].type, "image")
            self.assertEqual(result.content[1].mime_type, "image/png")
        finally:
            nas.close()
        with (
            tempfile.TemporaryDirectory() as directory,
            patch("tempfile.tempdir", directory),
        ):
            for kind in ("document", "image", "pdf"):
                with self.subTest(kind=kind), self.assertRaises(AdapterError):
                    if kind == "document":
                        _convert_document(b"corrupt", "x.docx", Limits())
                    elif kind == "image":
                        _image_content(b"corrupt", Limits())
                    else:
                        _pdf_page(b"corrupt", 1, Limits())
                self.assertEqual(list(Path(directory).iterdir()), [])
            with self.assertRaises(AdapterError):
                _convert_document(
                    _xlsx_fixture(), "x.xlsx", Limits(parser_timeout_seconds=0.001)
                )
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_nonblank_pdf_extracts_actual_words(self):
        """Ensure the production converter extracts text from a real PDF stream."""
        self.assertIn(
            "PDF fixture words",
            _convert_document(_minimal_pdf(text=True), "fixture.pdf", Limits()),
        )

    def test_pdf_dimensions_rejected_before_render(self):
        with self.assertRaises(AdapterError):
            _pdf_page(_minimal_pdf(), 1, Limits(image_pixels=1))

    def test_subprocess_output_timeout_and_secret_environment(self):
        safe = {"PATH": "/usr/bin:/bin"}
        self.assertIsNone(
            _bounded_process_output(
                [sys.executable, "-c", "print('x'*4096)"], 2, 100, safe
            )
        )
        self.assertIsNone(
            _bounded_process_output(
                [sys.executable, "-c", "import time; time.sleep(2)"], 0.01, 100, safe
            )
        )
        with patch.dict(os.environ, {"SYNOLOGY_PASSWORD": "fixture-secret-sentinel"}):
            result = _bounded_process_output(
                [
                    sys.executable,
                    "-c",
                    "import os; print('SYNOLOGY_PASSWORD' in os.environ)",
                ],
                2,
                100,
                safe,
            )
        self.assertEqual(result.strip(), b"False")

    def test_document_formats_extract_actual_words(self):
        docx = _zip_fixture(
            {
                "[Content_Types].xml": "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='xml' ContentType='application/xml'/><Override PartName='/word/document.xml' ContentType='application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'/></Types>",
                "word/document.xml": "<w:document xmlns:w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'><w:body><w:p><w:r><w:t>fixture docx</w:t></w:r></w:p></w:body></w:document>",
            }
        )
        for extension, data, words in (
            (".docx", docx, "fixture docx"),
            (".xlsx", _xlsx_fixture(), "fixture xlsx"),
            (".pptx", _pptx_fixture(), "fixture pptx"),
        ):
            with self.subTest(extension=extension):
                self.assertIn(
                    words, _convert_document(data, "fixture" + extension, Limits())
                )
        # A blank scanned PDF produces no text and remains readable as a page image.
        self.assertEqual(
            _convert_document(_minimal_pdf(), "scan.pdf", Limits()).strip(), ""
        )
        self.assertEqual(_pdf_page(_minimal_pdf(), 1, Limits()).type, "image")


class RangeTests(unittest.TestCase):
    """Use a sparse 80MiB MP4 whose moov box is past the full transfer budget."""

    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "tiny.mp4")
            subprocess.run(
                [
                    "ffmpeg",
                    "-loglevel",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=black:s=32x32:d=1",
                    "-c:v",
                    "mpeg4",
                    path,
                ],
                check=True,
                timeout=10,
            )
            data = Path(path).read_bytes()
        offset = 0
        while offset < len(data):
            size = int.from_bytes(data[offset : offset + 4], "big")
            if data[offset + 4 : offset + 8] == b"moov":
                break
            offset += size
        assert data[offset + 4 : offset + 8] == b"moov"
        cls.prefix, cls.moov = data[:offset], data[offset:]
        cls.padding_size = 80 * 1024 * 1024
        cls.free = struct.pack(">I4s", cls.padding_size, b"free")
        cls.tail_offset = len(cls.prefix) + cls.padding_size

    def nas(self, limits=None):
        nas = FixtureNAS(name="large.mp4", limits=limits)
        nas.size = self.tail_offset + len(self.moov)
        segments = (
            (0, self.prefix),
            (len(self.prefix), self.free),
            (self.tail_offset, self.moov),
        )

        def read(start, end):
            result = bytearray(end - start + 1)
            for offset, data in segments:
                begin, stop = max(start, offset), min(end + 1, offset + len(data))
                if begin < stop:
                    result[begin - start : stop - start] = data[
                        begin - offset : stop - offset
                    ]
            return bytes(result)

        nas.read_range = read
        return nas

    def test_tail_seek_discovers_large_video_within_budget(self):
        nas = self.nas()
        try:
            result = nas.client.media_info(nas.name)
            self.assertFalse(result["inspection_limited"], result)
            stream = result["ffprobe"]["streams"][0]
            self.assertEqual(
                (stream["codec_type"], stream["width"], stream["height"]),
                ("video", 32, 32),
            )
            self.assertTrue(
                any(start >= self.tail_offset for start, _ in nas.ranges), nas.ranges
            )
            self.assertLessEqual(result["transferred_bytes"], 64 * 1024 * 1024)
        finally:
            nas.close()

    def test_ignored_mismatched_and_truncated_ranges_return_limitation(self):
        for mode in ("ignored", "mismatch", "truncated"):
            nas = self.nas()
            nas.range_mode = mode
            try:
                result = nas.client.media_info(nas.name)
                self.assertTrue(result["inspection_limited"], mode)
                self.assertIn("limitation", result)
            finally:
                nas.close()

    def test_cumulative_range_budget_and_socket_cleanup(self):
        nas = self.nas(Limits(media_probe_bytes=100))
        try:
            nas.client.verify_root()
            facade = _RangeFacade(nas.client, "/Media/large.mp4", nas.size)
            with facade as url, httpx.Client(trust_env=False) as client:
                self.assertEqual(
                    client.get(url, headers={"range": "bytes=0-59"}).status_code,
                    206,
                )
                self.assertEqual(
                    client.get(url, headers={"range": "bytes=60-119"}).status_code,
                    416,
                )
            self.assertEqual(facade.used, 60)
            self.assertFalse(facade.active_handlers)
            self.assertFalse(facade.thread.is_alive())
            with self.assertRaises(httpx.ConnectError):
                httpx.get(url, trust_env=False)
        finally:
            nas.close()

    def test_close_waits_for_blocked_range_and_rejects_late_chunk(self):
        """Closing the facade joins an in-flight stream and discards late bytes."""
        nas = self.nas(Limits(media_probe_bytes=100))
        entered = threading.Event()
        facade = _RangeFacade(nas.client, "/Media/large.mp4", nas.size)
        responses = []

        def delayed_download(path, **kwargs):
            entered.set()
            if not facade.closed.wait(2):
                raise AssertionError("Facade did not signal cancellation")
            kwargs["on_bytes"](1)
            raise AssertionError("Late NAS data must be rejected")

        try:
            with patch.object(nas.client, "_download", side_effect=delayed_download):
                with facade as url:
                    request = threading.Thread(
                        target=lambda: responses.append(
                            httpx.get(
                                url,
                                headers={"range": "bytes=0-59"},
                                trust_env=False,
                                timeout=3,
                            ).status_code
                        )
                    )
                    request.start()
                    self.assertTrue(entered.wait(2))
                request.join(2)
            self.assertFalse(request.is_alive())
            self.assertEqual(responses, [502])
            self.assertEqual(facade.used, 0)
            self.assertFalse(facade.active_handlers)
            self.assertFalse(facade.thread.is_alive())
        finally:
            nas.close()

    def test_malicious_playlist_disguised_as_mp4_is_not_demuxed(self):
        with tempfile.NamedTemporaryFile(suffix=".mp4") as source:
            source.write(b"ffconcat version 1.0\nfile /etc/passwd\n")
            source.flush()
            self.assertIsNone(_ffprobe(source.name))
