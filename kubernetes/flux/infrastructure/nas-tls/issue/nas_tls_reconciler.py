#!/usr/bin/env python3
"""Safely reconcile the cert-manager certificate onto a Synology DSM endpoint.

The process deliberately uses only Python's standard library.  The mounted
certificate is validated before any DSM credential is read, and the DSM client
never follows redirects or places session material in a URL.  All exceptions
crossing the process boundary are reduced to fixed error codes so hostile DSM
responses cannot become log exfiltration.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import http.client
import json
import os
import re
import socket
import ssl
import stat
import sys
import threading
import time
import urllib.parse
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any


# Secret-bearing files and DSM responses are intentionally bounded.  These
# limits keep a malformed endpoint from consuming unbounded memory while still
# leaving ample room for a normal certificate chain and API envelope.
DEFAULT_FILE_LIMIT = 512 * 1024
DEFAULT_RESPONSE_LIMIT = 256 * 1024
DEFAULT_UPLOAD_LIMIT = 2 * 1024 * 1024
MAX_SECRET_LENGTH = 4096
DEFAULT_TIMEOUT_SECONDS = 15.0
DEFAULT_RETRY_COUNT = 4
DEFAULT_RETRY_DELAY_SECONDS = 5.0
DEFAULT_MINIMUM_LIFETIME_SECONDS = 14 * 24 * 60 * 60
ACTIVATION_PLACEHOLDER = "activation-required"
EXPECTED_HOSTNAME = "nas.bohdy.sk"
EXPECTED_PORT = 5001
MAX_CERTIFICATE_ID_LENGTH = 128
MAX_CERTIFICATE_DESCRIPTION_LENGTH = 256
MAX_SERVICE_FIELD_LENGTH = 256

_PEM_CERTIFICATE = re.compile(
    rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
    re.DOTALL,
)
_SAFE_ID = re.compile(r"[A-Za-z0-9_.:-]{1,128}\Z")


def _valid_session_value(value: str) -> bool:
    """Accept RFC cookie-octets while excluding header/cookie separators."""

    return bool(value) and len(value) <= MAX_SECRET_LENGTH and all(
        0x21 <= ord(character) <= 0x7E and character not in {"\"", ",", ";", "\\"}
        for character in value
    )

# DSM's discovery response must identify only the API paths this client has a
# reviewed contract for.  Certificate APIs are fixed to version 1; the auth
# API has been published with versions 1 through 7 and the returned maximum is
# used for the login call after this bounded check.
DISCOVERY_PATHS = {
    "SYNO.API.Auth": frozenset({"auth.cgi", "entry.cgi"}),
    "SYNO.Core.Certificate.CRT": frozenset({"entry.cgi"}),
    "SYNO.Core.Certificate": frozenset({"entry.cgi"}),
}
DISCOVERY_MAX_VERSIONS = {
    "SYNO.Core.Certificate.CRT": 1,
    "SYNO.Core.Certificate": 1,
}


class ReconcileError(Exception):
    """An expected, sanitized failure suitable for the process exit path."""

    def __init__(self, code: str) -> None:
        # Error codes are fixed strings so no remote response or secret can be
        # accidentally included in stderr, events, or a CronJob log.
        super().__init__(code)
        self.code = code


def _fail(code: str) -> None:
    raise ReconcileError(code)


def _bounded_bytes(path: str, limit: int = DEFAULT_FILE_LIMIT) -> bytes:
    """Read one bounded file snapshot without ever printing its contents."""

    try:
        with open(path, "rb") as handle:
            value = handle.read(limit + 1)
    except (OSError, ValueError):
        _fail("source_read_failed")
    if len(value) > limit:
        _fail("source_too_large")
    return value


def _decode_json(value: bytes, code: str) -> Any:
    """Decode JSON while rejecting non-standard constants and bad UTF-8."""

    try:
        return json.loads(
            value.decode("utf-8"),
            parse_constant=lambda _constant: (_ for _ in ()).throw(
                ValueError("non-standard JSON constant")
            ),
        )
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError):
        _fail(code)


def _required_string(value: Mapping[str, Any], key: str, limit: int = MAX_SECRET_LENGTH) -> str:
    """Return a bounded configuration string and reject control characters."""

    candidate = value.get(key)
    if not isinstance(candidate, str) or not candidate or len(candidate) > limit:
        _fail("config_invalid")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in candidate):
        _fail("config_invalid")
    return candidate


@dataclasses.dataclass(frozen=True)
class Config:
    """Non-secret reconciler settings loaded from a reviewed ConfigMap."""

    hostname: str = EXPECTED_HOSTNAME
    port: int = EXPECTED_PORT
    source_cert: str = "/source/tls.crt"
    source_key: str = "/source/tls.key"
    auth_directory: str = "/auth"
    target_description: str = "nas.bohdy.sk cert-manager"
    target_id: str = ACTIVATION_PLACEHOLDER
    minimum_lifetime_seconds: int = DEFAULT_MINIMUM_LIFETIME_SECONDS
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
    response_limit_bytes: int = DEFAULT_RESPONSE_LIMIT
    upload_limit_bytes: int = DEFAULT_UPLOAD_LIMIT
    retry_count: int = DEFAULT_RETRY_COUNT
    retry_delay_seconds: float = DEFAULT_RETRY_DELAY_SECONDS
    ca_file: str | None = None

    @classmethod
    def from_file(cls, path: str) -> "Config":
        """Load the reviewed JSON contract without accepting unknown fields."""

        raw_bytes = _bounded_bytes(path, 64 * 1024)
        raw = _decode_json(raw_bytes, "config_invalid")
        if not isinstance(raw, dict):
            _fail("config_invalid")
        allowed = {
            "hostname",
            "port",
            "source_cert",
            "source_key",
            "auth_directory",
            "target_description",
            "target_id",
            "minimum_lifetime_seconds",
            "timeout_seconds",
            "response_limit_bytes",
            "upload_limit_bytes",
            "retry_count",
            "retry_delay_seconds",
        }
        if set(raw) - allowed:
            _fail("config_invalid")
        required = {
            "hostname",
            "port",
            "source_cert",
            "source_key",
            "auth_directory",
            "target_description",
            "target_id",
        }
        if required - set(raw):
            _fail("config_invalid")
        try:
            result = cls(
                hostname=_required_string(raw, "hostname", 253),
                port=raw["port"],
                source_cert=_required_string(raw, "source_cert", 512),
                source_key=_required_string(raw, "source_key", 512),
                auth_directory=_required_string(raw, "auth_directory", 512),
                target_description=_required_string(raw, "target_description", 256),
                target_id=_required_string(raw, "target_id", 128),
                minimum_lifetime_seconds=raw.get(
                    "minimum_lifetime_seconds", DEFAULT_MINIMUM_LIFETIME_SECONDS
                ),
                timeout_seconds=raw.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS),
                response_limit_bytes=raw.get("response_limit_bytes", DEFAULT_RESPONSE_LIMIT),
                upload_limit_bytes=raw.get("upload_limit_bytes", DEFAULT_UPLOAD_LIMIT),
                retry_count=raw.get("retry_count", DEFAULT_RETRY_COUNT),
                retry_delay_seconds=raw.get("retry_delay_seconds", DEFAULT_RETRY_DELAY_SECONDS),
            )
        except (TypeError, ValueError):
            _fail("config_invalid")
        validate_config(result)
        return result


def validate_config(config: Config) -> None:
    """Keep production routing fixed and numeric limits conservative."""

    if config.hostname != EXPECTED_HOSTNAME or config.port != EXPECTED_PORT:
        _fail("config_invalid")
    for path in (config.source_cert, config.source_key, config.auth_directory):
        if not path.startswith("/") or "\x00" in path:
            _fail("config_invalid")
    if not isinstance(config.target_id, str) or len(config.target_id) > 128:
        _fail("config_invalid")
    if (
        not isinstance(config.target_description, str)
        or not config.target_description
        or len(config.target_description) > 256
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in config.target_description)
    ):
        _fail("config_invalid")
    if not isinstance(config.minimum_lifetime_seconds, int) or not (
        60 <= config.minimum_lifetime_seconds <= 90 * 24 * 60 * 60
    ):
        _fail("config_invalid")
    if not isinstance(config.timeout_seconds, (int, float)) or not (
        1 <= float(config.timeout_seconds) <= 60
    ):
        _fail("config_invalid")
    if not isinstance(config.response_limit_bytes, int) or not (
        4096 <= config.response_limit_bytes <= 2 * 1024 * 1024
    ):
        _fail("config_invalid")
    if not isinstance(config.upload_limit_bytes, int) or not (
        64 * 1024 <= config.upload_limit_bytes <= 8 * 1024 * 1024
    ):
        _fail("config_invalid")
    if not isinstance(config.retry_count, int) or not (1 <= config.retry_count <= 8):
        _fail("config_invalid")
    if not isinstance(config.retry_delay_seconds, (int, float)) or not (
        0 <= float(config.retry_delay_seconds) <= 60
    ):
        _fail("config_invalid")
    if config.ca_file is not None and (
        not isinstance(config.ca_file, str)
        or not config.ca_file.startswith("/")
        or "\x00" in config.ca_file
    ):
        _fail("config_invalid")


def _stat_signature(path: str) -> tuple[int, int, int, int, int]:
    """Capture the immutable Secret projection identity used by a snapshot."""

    try:
        metadata = os.stat(path)
    except OSError:
        _fail("source_changed")
    if not stat.S_ISREG(metadata.st_mode):
        _fail("source_changed")
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_mode,
    )


def _directory_signature(path: str) -> tuple[int, int, int, int]:
    """Capture the projected parent identity without reading Secret contents."""

    try:
        metadata = os.stat(path)
    except OSError:
        _fail("source_changed")
    if not stat.S_ISDIR(metadata.st_mode):
        _fail("source_changed")
    return (metadata.st_dev, metadata.st_ino, metadata.st_mtime_ns, metadata.st_mode)


@dataclasses.dataclass(frozen=True)
class SourceSnapshot:
    """One cert-manager Secret projection captured for the whole operation."""

    cert_path: str
    key_path: str
    configured_cert_path: str
    configured_key_path: str
    projection_directory: str
    cert_pem: bytes
    key_pem: bytes
    leaf_pem: bytes
    intermediate_pem: bytes
    leaf_der: bytes
    fingerprint: str
    projection_stat: tuple[int, int, int, int]
    cert_stat: tuple[int, int, int, int, int]
    key_stat: tuple[int, int, int, int, int]

    def assert_stable(self) -> None:
        """Fail closed if kubelet rotated or removed either source file."""

        # A Secret volume swaps the top-level symlinks to a new `..data`
        # directory.  Keep using the captured directory, but reject a swap so
        # the upload cannot silently lag behind the current cert-manager Secret.
        if (
            os.path.realpath(self.configured_cert_path) != self.cert_path
            or os.path.realpath(self.configured_key_path) != self.key_path
        ):
            _fail("source_changed")
        if _directory_signature(self.projection_directory) != self.projection_stat:
            _fail("source_changed")
        if _stat_signature(self.cert_path) != self.cert_stat:
            _fail("source_changed")
        if _stat_signature(self.key_path) != self.key_stat:
            _fail("source_changed")


def _split_certificate_chain(value: bytes) -> tuple[bytes, bytes, bytes]:
    """Return leaf PEM, intermediate PEM, and leaf DER from a fullchain."""

    matches = [match.group(0) for match in _PEM_CERTIFICATE.finditer(value)]
    if not matches:
        _fail("source_chain_invalid")
    # cert-manager's tls.crt is a PEM chain and must not contain unrelated
    # bytes, which could otherwise be silently dropped before DSM import.
    remainder = _PEM_CERTIFICATE.sub(b"", value)
    if remainder.strip():
        _fail("source_chain_invalid")
    try:
        leaf_der = ssl.PEM_cert_to_DER_cert(matches[0].decode("ascii"))
    except (UnicodeDecodeError, ValueError):
        _fail("source_chain_invalid")
    return matches[0], b"\n".join(matches[1:]), leaf_der


def load_source_snapshot(config: Config) -> SourceSnapshot:
    """Resolve and read both files from one immutable Secret projection."""

    cert_path = os.path.realpath(config.source_cert)
    key_path = os.path.realpath(config.source_key)
    cert_directory = os.path.dirname(cert_path)
    key_directory = os.path.dirname(key_path)
    source_directory = os.path.realpath(os.path.dirname(config.source_cert))
    if not cert_directory or cert_directory != key_directory:
        _fail("source_projection_mismatch")
    try:
        if os.path.commonpath((source_directory, cert_path)) != source_directory:
            _fail("source_projection_mismatch")
        if os.path.commonpath((source_directory, key_path)) != source_directory:
            _fail("source_projection_mismatch")
    except ValueError:
        _fail("source_projection_mismatch")
    projection_stat = _directory_signature(cert_directory)
    cert_stat = _stat_signature(cert_path)
    key_stat = _stat_signature(key_path)
    cert_pem = _bounded_bytes(cert_path)
    key_pem = _bounded_bytes(key_path)
    leaf_pem, intermediate_pem, leaf_der = _split_certificate_chain(cert_pem)
    snapshot = SourceSnapshot(
        cert_path=cert_path,
        key_path=key_path,
        configured_cert_path=config.source_cert,
        configured_key_path=config.source_key,
        projection_directory=cert_directory,
        cert_pem=cert_pem,
        key_pem=key_pem,
        leaf_pem=leaf_pem,
        intermediate_pem=intermediate_pem,
        leaf_der=leaf_der,
        fingerprint=hashlib.sha256(leaf_der).hexdigest(),
        projection_stat=projection_stat,
        cert_stat=cert_stat,
        key_stat=key_stat,
    )
    snapshot.assert_stable()
    return snapshot


def _client_context(config: Config) -> ssl.SSLContext:
    """Use system trust in production or an explicitly supplied test CA."""

    try:
        context = ssl.create_default_context(cafile=config.ca_file)
    except (OSError, ssl.SSLError):
        _fail("trust_store_invalid")
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.check_hostname = True
    return context


def _validate_peer_dates(peer: Mapping[str, Any], config: Config) -> None:
    """Check the peer-decoded validity window and required remaining lifetime."""

    not_before = peer.get("notBefore")
    not_after = peer.get("notAfter")
    if not isinstance(not_before, str) or not isinstance(not_after, str):
        _fail("source_certificate_dates_invalid")
    try:
        start = ssl.cert_time_to_seconds(not_before)
        end = ssl.cert_time_to_seconds(not_after)
    except (TypeError, ValueError, OverflowError):
        _fail("source_certificate_dates_invalid")
    now = time.time()
    if start > now:
        _fail("source_certificate_not_yet_valid")
    if end <= now:
        _fail("source_certificate_expired")
    if end - now < config.minimum_lifetime_seconds:
        _fail("source_certificate_lifetime_short")


def validate_source_snapshot(config: Config, snapshot: SourceSnapshot) -> None:
    """Prove key matching, chain validity, hostname, dates, and lifetime."""

    snapshot.assert_stable()
    server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.minimum_version = ssl.TLSVersion.TLSv1_2
    try:
        # OpenSSL reads the resolved projection directory, never the mutable
        # kubelet symlink.  The stat check immediately afterward catches a
        # projection disappearing or changing during this operation.
        server_context.load_cert_chain(snapshot.cert_path, snapshot.key_path)
    except (OSError, ssl.SSLError, ValueError):
        _fail("source_key_mismatch")
    snapshot.assert_stable()

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(float(config.timeout_seconds))
    port = listener.getsockname()[1]
    server_error: list[BaseException] = []

    def accept_once() -> None:
        try:
            raw_socket, _peer = listener.accept()
            raw_socket.settimeout(float(config.timeout_seconds))
            with server_context.wrap_socket(raw_socket, server_side=True):
                # The client only needs a bounded handshake; no application
                # payload is exchanged on this validation socket.
                pass
        except BaseException as error:  # pragma: no cover - exercised by OS failures
            server_error.append(error)

    worker = threading.Thread(target=accept_once, name="nas-tls-source-check", daemon=True)
    worker.start()
    try:
        client_context = _client_context(config)
        with socket.create_connection(("127.0.0.1", port), float(config.timeout_seconds)) as raw:
            with client_context.wrap_socket(raw, server_hostname=config.hostname) as tls_socket:
                peer_der = tls_socket.getpeercert(binary_form=True)
                peer = tls_socket.getpeercert()
        if peer_der != snapshot.leaf_der:
            _fail("source_handshake_mismatch")
        if not isinstance(peer, dict):
            _fail("source_certificate_schema_invalid")
        _validate_peer_dates(peer, config)
    except ReconcileError:
        raise
    except (OSError, ssl.SSLError, ValueError):
        _fail("source_tls_invalid")
    finally:
        listener.close()
        worker.join(timeout=float(config.timeout_seconds))
    if server_error:
        _fail("source_tls_invalid")
    snapshot.assert_stable()


class _RoutedHTTPSConnection(http.client.HTTPSConnection):
    """Connect to a test route while retaining the production SNI hostname."""

    def __init__(
        self,
        logical_host: str,
        connect_host: str,
        port: int,
        context: ssl.SSLContext,
        timeout: float,
    ) -> None:
        super().__init__(connect_host, port=port, context=context, timeout=timeout)
        self._logical_host = logical_host
        self._connect_host = connect_host

    def connect(self) -> None:  # pragma: no cover - production path is exercised by integration
        if self._tunnel_host:
            super().connect()
            return
        raw_socket = socket.create_connection(
            (self._connect_host, self.port), timeout=self.timeout
        )
        self.sock = self._context.wrap_socket(raw_socket, server_hostname=self._logical_host)


@dataclasses.dataclass(frozen=True)
class Discovery:
    """Validated API paths and version for one DSM instance."""

    auth_path: str
    auth_version: int


@dataclasses.dataclass(frozen=True)
class Session:
    """Ephemeral DSM session material kept only in process memory."""

    sid: str
    syno_token: str


@dataclasses.dataclass(frozen=True)
class TargetSnapshot:
    """Identity and bindings that must survive an in-place import."""

    certificate_id: str
    description: str
    is_default: bool
    services: tuple[Any, ...]

    def same_bindings(self, other: "TargetSnapshot") -> bool:
        return (
            self.certificate_id == other.certificate_id
            and self.description == other.description
            and self.is_default == other.is_default
            and _normalize_services(self.services) == _normalize_services(other.services)
        )


ServiceIdentity = tuple[str, str, bool]


def _wire_text(value: Any, limit: int) -> str:
    """Accept bounded DSM text without allowing control characters in state."""

    if (
        not isinstance(value, str)
        or not value
        or len(value) > limit
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    ):
        _fail("certificate_list_schema_invalid")
    return value


def _service_flag(value: Any) -> bool:
    """Normalize the bool forms accepted by the provider's DSM parser."""

    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.lower() in {"true", "false", "1", "0"}:
        return value.lower() in {"true", "1"}
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value in {0, 1}:
        return bool(value)
    _fail("certificate_list_schema_invalid")


def _service_identity(service: Any) -> ServiceIdentity:
    """Return owner/service/package identity used to detect duplicate bindings.

    The maintained provider parses DSM service objects with ``service``,
    ``display_name``, ``owner``, and ``isPkg`` fields.  A service label alone is
    not globally unique when different owners share it, so owner and package
    status remain part of the identity.  Legacy string fixtures are retained as
    the empty-owner, non-package form.
    """

    if isinstance(service, str):
        return ("", _wire_text(service, MAX_SERVICE_FIELD_LENGTH), False)
    if not isinstance(service, dict):
        _fail("certificate_list_schema_invalid")
    service_name = _wire_text(service.get("service"), MAX_SERVICE_FIELD_LENGTH)
    owner_value = service.get("owner", "")
    display_name = service.get("display_name", "")
    if not isinstance(owner_value, str) or len(owner_value) > MAX_SERVICE_FIELD_LENGTH:
        _fail("certificate_list_schema_invalid")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in owner_value):
        _fail("certificate_list_schema_invalid")
    if not isinstance(display_name, str) or len(display_name) > MAX_SERVICE_FIELD_LENGTH:
        _fail("certificate_list_schema_invalid")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in display_name):
        _fail("certificate_list_schema_invalid")
    is_package = _service_flag(service.get("isPkg", False))
    return (owner_value, service_name, is_package)


def _normalize_services(services: Any) -> tuple[Any, ...]:
    """Canonicalize service objects and reject duplicate composite bindings."""

    if not isinstance(services, (list, tuple)):
        _fail("certificate_list_schema_invalid")
    seen: set[ServiceIdentity] = set()
    normalized: list[tuple[ServiceIdentity, str, Any]] = []
    for service in services:
        identity = _service_identity(service)
        if identity in seen:
            _fail("certificate_inventory_ambiguous")
        seen.add(identity)
        if isinstance(service, dict):
            # Normalize parser-supported aliases while retaining every raw
            # field so before/after comparison still covers the whole binding.
            canonical = dict(service)
            canonical["service"] = identity[1]
            canonical["owner"] = identity[0]
            canonical["display_name"] = service.get("display_name", "")
            canonical["isPkg"] = identity[2]
        else:
            canonical = service
        try:
            encoded = json.dumps(
                canonical, sort_keys=True, separators=(",", ":"), ensure_ascii=True
            )
        except (TypeError, ValueError):
            _fail("certificate_list_schema_invalid")
        if len(encoded.encode("utf-8")) > 16 * 1024:
            _fail("certificate_list_schema_invalid")
        normalized.append((identity, encoded, canonical))
    normalized.sort(key=lambda item: (item[0], item[1]))
    return tuple(item[2] for item in normalized)


def _inventory_signature(certificates: list[TargetSnapshot]) -> tuple[Any, ...]:
    """Normalize every id/default/service binding for before/after comparison."""

    if not certificates:
        _fail("certificate_list_schema_invalid")
    seen_ids: set[str] = set()
    seen_services: set[ServiceIdentity] = set()
    defaults = 0
    signature: list[tuple[str, str, bool, str]] = []
    for certificate in certificates:
        if certificate.certificate_id in seen_ids:
            _fail("certificate_inventory_ambiguous")
        seen_ids.add(certificate.certificate_id)
        if certificate.is_default:
            defaults += 1
        normalized_services = _normalize_services(certificate.services)
        for service in normalized_services:
            identity = _service_identity(service)
            if identity in seen_services:
                _fail("certificate_inventory_ambiguous")
            seen_services.add(identity)
        try:
            services_json = json.dumps(
                normalized_services, sort_keys=True, separators=(",", ":"), ensure_ascii=True
            )
        except (TypeError, ValueError):
            _fail("certificate_list_schema_invalid")
        signature.append(
            (certificate.certificate_id, certificate.description, certificate.is_default, services_json)
        )
    if defaults != 1:
        _fail("certificate_inventory_ambiguous")
    return tuple(sorted(signature))


ConnectionFactory = Callable[[Config, ssl.SSLContext], http.client.HTTPSConnection]
SocketFactory = Callable[[tuple[str, int], float], socket.socket]


class DsmClient:
    """Small, strict HTTP client for the reviewed DSM certificate APIs."""

    def __init__(
        self,
        config: Config,
        *,
        connect_host: str | None = None,
        connection_factory: ConnectionFactory | None = None,
        socket_factory: SocketFactory | None = None,
    ) -> None:
        validate_config(config)
        self.config = config
        self.context = _client_context(config)
        self.connect_host = connect_host or config.hostname
        self.connection_factory = connection_factory
        self.socket_factory = socket_factory or socket.create_connection

    def _connection(self) -> http.client.HTTPSConnection:
        if self.connection_factory is not None:
            return self.connection_factory(self.config, self.context)
        if self.connect_host == self.config.hostname:
            return http.client.HTTPSConnection(
                self.config.hostname,
                port=self.config.port,
                context=self.context,
                timeout=float(self.config.timeout_seconds),
            )
        return _RoutedHTTPSConnection(
            self.config.hostname,
            self.connect_host,
            self.config.port,
            self.context,
            float(self.config.timeout_seconds),
        )

    def served_fingerprint(self) -> str:
        """Strictly verify DSM TLS and return the served leaf fingerprint."""

        raw_socket: socket.socket | None = None
        try:
            raw_socket = self.socket_factory(
                (self.connect_host, self.config.port), float(self.config.timeout_seconds)
            )
            raw_socket.settimeout(float(self.config.timeout_seconds))
            with self.context.wrap_socket(
                raw_socket, server_hostname=self.config.hostname
            ) as tls_socket:
                peer_der = tls_socket.getpeercert(binary_form=True)
        except ReconcileError:
            raise
        except (OSError, ssl.SSLError, ValueError):
            _fail("dsm_tls_verification_failed")
        finally:
            if raw_socket is not None:
                try:
                    raw_socket.close()
                except OSError:
                    pass
        if not peer_der:
            _fail("dsm_tls_verification_failed")
        return hashlib.sha256(peer_der).hexdigest()

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> bytes:
        """Issue one bounded request with no redirect handling."""

        connection = self._connection()
        try:
            connection.request(method, path, body=body, headers=dict(headers or {}))
            response = connection.getresponse()
            if 300 <= response.status < 400:
                _fail("redirect_rejected")
            if response.status != 200:
                _fail("http_status_unexpected")
            content_length = response.getheader("Content-Length")
            if content_length is not None:
                try:
                    if int(content_length) > self.config.response_limit_bytes:
                        _fail("response_too_large")
                except ValueError:
                    _fail("response_invalid")
            value = response.read(self.config.response_limit_bytes + 1)
            if len(value) > self.config.response_limit_bytes:
                _fail("response_too_large")
            return value
        except ReconcileError:
            raise
        except (OSError, ssl.SSLError, http.client.HTTPException, ValueError):
            _fail("dsm_transport_failed")
        finally:
            try:
                connection.close()
            except OSError:
                pass

    def _json_request(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        return _decode_json(self._request(method, path, body=body, headers=headers), "response_invalid")

    @staticmethod
    def _envelope(value: Any) -> Mapping[str, Any]:
        if not isinstance(value, dict) or value.get("success") is not True:
            _fail("api_error")
        data = value.get("data")
        if not isinstance(data, dict):
            _fail("response_schema_invalid")
        return data

    def discover(self) -> Discovery:
        """Discover and whitelist auth and certificate API paths first."""

        query = urllib.parse.urlencode(
            {
                "api": "SYNO.API.Info",
                "version": "1",
                "method": "query",
                "query": ",".join(DISCOVERY_PATHS),
            }
        )
        result = self._envelope(
            self._json_request("GET", f"/webapi/query.cgi?{query}")
        )
        validated: dict[str, tuple[str, int]] = {}
        for api_name, allowed_paths in DISCOVERY_PATHS.items():
            entry = result.get(api_name)
            if not isinstance(entry, dict):
                _fail("discovery_schema_invalid")
            path = entry.get("path")
            min_version = entry.get("minVersion")
            max_version = entry.get("maxVersion")
            if (
                not isinstance(path, str)
                or path not in allowed_paths
                or not isinstance(min_version, int)
                or isinstance(min_version, bool)
                or not isinstance(max_version, int)
                or isinstance(max_version, bool)
                or not (1 <= min_version <= max_version <= 7)
            ):
                _fail("discovery_contract_invalid")
            selected_version = DISCOVERY_MAX_VERSIONS.get(api_name, max_version)
            if min_version > selected_version or max_version < selected_version:
                _fail("discovery_contract_invalid")
            if api_name in DISCOVERY_MAX_VERSIONS and (
                min_version != selected_version or max_version != selected_version
            ):
                _fail("discovery_contract_invalid")
            validated[api_name] = (path, max_version)
        auth_path, auth_version = validated["SYNO.API.Auth"]
        return Discovery(auth_path=auth_path, auth_version=auth_version)

    @staticmethod
    def _session_headers(session: Session) -> dict[str, str]:
        # The official WebAPI contract permits the SID in the `id` cookie and
        # the SynoToken in this header. Keeping both out of the URL prevents
        # reverse-proxy and DSM access logs from becoming credential stores.
        return {
            "Content-Type": "application/x-www-form-urlencoded",
            "X-SYNO-TOKEN": session.syno_token,
            "Cookie": f"id={session.sid}",
        }

    def login(self, discovery: Discovery, username: str, password: str) -> Session:
        """Authenticate with a POST body and require both expected fields."""

        form = {
            "api": "SYNO.API.Auth",
            "version": str(discovery.auth_version),
            "method": "login",
            "format": "sid",
            "enable_syno_token": "yes",
            "account": username,
            "passwd": password,
        }
        path = f"/webapi/{discovery.auth_path}?enable_syno_token=yes"
        value = self._envelope(
            self._json_request(
                "POST",
                path,
                body=urllib.parse.urlencode(form).encode("utf-8"),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
        )
        sid = value.get("sid")
        syno_token = value.get("synotoken")
        if (
            not isinstance(sid, str)
            or not sid
            or not _valid_session_value(sid)
            or not isinstance(syno_token, str)
            or not syno_token
            or not _valid_session_value(syno_token)
        ):
            _fail("auth_response_invalid")
        return Session(sid=sid, syno_token=syno_token)

    def _authenticated_form(
        self, session: Session, api: str, method: str, version: str = "1"
    ) -> tuple[str, bytes, dict[str, str]]:
        """Build a public selector URL and keep session selectors in headers."""

        path = "/webapi/entry.cgi?" + urllib.parse.urlencode(
            {"api": api, "method": method, "version": version}
        )
        form = {"api": api, "method": method, "version": version}
        return (
            path,
            urllib.parse.urlencode(form).encode("utf-8"),
            self._session_headers(session),
        )

    def list_certificates(self, session: Session) -> list[TargetSnapshot]:
        path, body, headers = self._authenticated_form(
            session, "SYNO.Core.Certificate.CRT", "list"
        )
        value = self._envelope(self._json_request("POST", path, body=body, headers=headers))
        certificates = value.get("certificates")
        if not isinstance(certificates, list):
            _fail("certificate_list_schema_invalid")
        result: list[TargetSnapshot] = []
        for entry in certificates:
            if not isinstance(entry, dict):
                _fail("certificate_list_schema_invalid")
            certificate_id = entry.get("id")
            description = entry.get("desc")
            is_default = entry.get("is_default")
            services = entry.get("services")
            if (
                not isinstance(certificate_id, str)
                or not certificate_id
                or not isinstance(description, str)
                or not isinstance(is_default, bool)
                or not isinstance(services, list)
            ):
                _fail("certificate_list_schema_invalid")
            _wire_text(certificate_id, MAX_CERTIFICATE_ID_LENGTH)
            _wire_text(description, MAX_CERTIFICATE_DESCRIPTION_LENGTH)
            stable_services = _normalize_services(services)
            result.append(
                TargetSnapshot(
                    certificate_id=certificate_id,
                    description=description,
                    is_default=is_default,
                    services=stable_services,
                )
            )
        _inventory_signature(result)
        return result

    def import_certificate(
        self, session: Session, target: TargetSnapshot, snapshot: SourceSnapshot
    ) -> None:
        """Upload the captured chain/key while preserving target identity."""

        boundary = "nas_tls_" + os.urandom(16).hex()
        fields: list[tuple[str, bytes, str | None, str]] = [
            ("key", snapshot.key_pem, "key.pem", "application/octet-stream"),
            ("cert", snapshot.leaf_pem, "cert.pem", "application/octet-stream"),
        ]
        if snapshot.intermediate_pem:
            fields.append(
                ("inter_cert", snapshot.intermediate_pem, "chain.pem", "application/octet-stream")
            )
        fields.extend(
            [
                ("id", target.certificate_id.encode("utf-8"), None, "text/plain"),
                ("desc", target.description.encode("utf-8"), None, "text/plain"),
                ("api", b"SYNO.Core.Certificate", None, "text/plain"),
                ("method", b"import", None, "text/plain"),
                ("version", b"1", None, "text/plain"),
            ]
        )
        if target.is_default:
            # Sending false would claim ownership of the default flag on some
            # DSM releases, so the false case is deliberately omitted.
            fields.append(("as_default", b"true", None, "text/plain"))
        body = bytearray()
        delimiter = boundary.encode("ascii")
        for name, value, filename, content_type in fields:
            body.extend(b"--" + delimiter + b"\r\n")
            if filename is None:
                body.extend(
                    f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("ascii")
                )
            else:
                body.extend(
                    f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                    f"Content-Type: {content_type}\r\n\r\n".encode("ascii")
                )
            body.extend(value)
            body.extend(b"\r\n")
        body.extend(b"--" + delimiter + b"--\r\n")
        if len(body) > self.config.upload_limit_bytes:
            _fail("upload_too_large")
        path = "/webapi/entry.cgi?" + urllib.parse.urlencode(
            {"api": "SYNO.Core.Certificate", "method": "import", "version": "1"}
        )
        headers = {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "X-SYNO-TOKEN": session.syno_token,
            "Cookie": f"id={session.sid}",
        }
        self._success_data(self._json_request("POST", path, body=bytes(body), headers=headers))

    @staticmethod
    def _success_data(value: Any) -> Mapping[str, Any]:
        """Accept DSM's successful empty-data mutation envelope safely."""

        if not isinstance(value, dict) or value.get("success") is not True:
            _fail("api_error")
        data = value.get("data", {})
        if data is None:
            data = {}
        if not isinstance(data, dict):
            _fail("response_schema_invalid")
        return data

    def logout(self, discovery: Discovery, session: Session) -> None:
        """Best-effort logout that never exposes the session in an error."""

        form = {
            "api": "SYNO.API.Auth",
            "version": str(discovery.auth_version),
            "method": "logout",
        }
        path = f"/webapi/{discovery.auth_path}?" + urllib.parse.urlencode(
            {"api": "SYNO.API.Auth", "method": "logout", "version": str(discovery.auth_version)}
        )
        try:
            self._success_data(self._json_request(
                "POST",
                path,
                body=urllib.parse.urlencode(form).encode("utf-8"),
                headers=self._session_headers(session),
            ))
        except ReconcileError:
            pass


def _read_auth(config: Config) -> tuple[str, str]:
    """Read DSM credentials once into memory from the operator Secret mount."""

    values = []
    for name in ("username", "password"):
        value = _bounded_bytes(os.path.join(config.auth_directory, name), MAX_SECRET_LENGTH)
        try:
            text = value.decode("utf-8")
        except UnicodeDecodeError:
            _fail("auth_secret_invalid")
        if not text or any(character in text for character in "\r\n\x00"):
            _fail("auth_secret_invalid")
        values.append(text)
    return values[0], values[1]


def _target_for_import(config: Config, certificates: list[TargetSnapshot]) -> TargetSnapshot:
    """Require an operator-pinned id and exactly one matching description."""

    if config.target_id == ACTIVATION_PLACEHOLDER or not _SAFE_ID.fullmatch(config.target_id):
        _fail("target_id_not_pinned")
    matches = [item for item in certificates if item.description == config.target_description]
    if not matches:
        _fail("target_missing")
    if len(matches) != 1:
        _fail("target_duplicate")
    target = matches[0]
    if target.certificate_id != config.target_id:
        _fail("target_id_mismatch")
    return target


def _validate_target_pin(config: Config) -> None:
    """Reject the activation placeholder before even a successful no-op run."""

    if config.target_id == ACTIVATION_PLACEHOLDER or not _SAFE_ID.fullmatch(config.target_id):
        _fail("target_id_not_pinned")


def reconcile(config: Config, *, client: DsmClient | None = None, sleep: Callable[[float], None] = time.sleep) -> str:
    """Validate source material, then perform a no-op or pinned in-place import."""

    validate_config(config)
    snapshot = load_source_snapshot(config)
    validate_source_snapshot(config, snapshot)
    _validate_target_pin(config)
    dsm = client or DsmClient(config)
    # This strict handshake is deliberately before discovery, authentication,
    # or any other credential request.  It also keeps routine runs credential-
    # free when DSM already serves the exact source leaf.
    if dsm.served_fingerprint() == snapshot.fingerprint:
        return "noop"

    discovery = dsm.discover()
    username, password = _read_auth(config)
    session = dsm.login(discovery, username, password)
    try:
        before_certificates = dsm.list_certificates(session)
        before_inventory = _inventory_signature(before_certificates)
        before = _target_for_import(config, before_certificates)
        snapshot.assert_stable()
        dsm.import_certificate(session, before, snapshot)
        last_failure = "post_import_verification_failed"
        for attempt in range(config.retry_count):
            try:
                snapshot.assert_stable()
                after_certificates = dsm.list_certificates(session)
                after_inventory = _inventory_signature(after_certificates)
                after = _target_for_import(config, after_certificates)
                if before_inventory != after_inventory or not before.same_bindings(after):
                    _fail("certificate_inventory_changed")
                if dsm.served_fingerprint() == snapshot.fingerprint:
                    return "rotated"
                last_failure = "served_certificate_mismatch"
            except ReconcileError as error:
                last_failure = error.code
            if attempt + 1 < config.retry_count:
                sleep(float(config.retry_delay_seconds))
        _fail(last_failure)
    finally:
        dsm.logout(discovery, session)


def main(argv: list[str] | None = None) -> int:
    """Run once and emit only a fixed success or error message."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    args = parser.parse_args(argv)
    try:
        result = reconcile(Config.from_file(args.config))
    except ReconcileError as error:
        print(f"nas-tls delivery failed: {error.code}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, SystemExit):
        raise
    except Exception:
        # No traceback: unexpected exceptions can carry a hostile response,
        # filesystem path, or secret-bearing library diagnostic.
        print("nas-tls delivery failed: internal_error", file=sys.stderr)
        return 1
    print(f"nas-tls delivery: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
