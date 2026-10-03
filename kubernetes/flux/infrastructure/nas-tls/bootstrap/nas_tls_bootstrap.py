#!/usr/bin/env python3
"""Inspect or import the cert-manager certificate through the first DSM channel.

The default mode is a read-only inventory.  ``--import-once`` is the only mode
that can submit a DSM import, and it deliberately uses an unverified fixed-IP
TLS channel for that one initial operation because the existing DSM leaf is the
explicit first-import exception.  Source material is still validated by the
shared strict reconciler before any credential or network operation.  After an
import attempt the unverified client is permanently sealed; only fresh,
hostname-verified clients may perform bounded read-back checks.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import importlib.util
import json
import socket
import ssl
import sys
import time
import urllib.parse
from pathlib import Path
from types import ModuleType
from typing import Any, Callable


BOOTSTRAP_CONNECT_HOST = "10.1.100.10"
BOOTSTRAP_HOSTNAME = "nas.bohdy.sk"
BOOTSTRAP_PORT = 5001
MAX_INVENTORY_OUTPUT_BYTES = 128 * 1024


def _load_common_reconciler() -> ModuleType:
    """Load the single shared strict source/API implementation.

    The bootstrap ConfigMap contains this small wrapper only.  The issue-owned
    ConfigMap supplies ``nas_tls_reconciler.py`` at ``/app`` in the Job, while
    the repository-relative path keeps the wrapper directly testable offline.
    """

    existing = sys.modules.get("nas_tls_reconciler")
    if existing is not None:
        return existing
    candidates = (
        Path("/app/nas_tls_reconciler.py"),
        Path(__file__).parents[1] / "issue" / "nas_tls_reconciler.py",
    )
    for candidate in candidates:
        if not candidate.is_file():
            continue
        spec = importlib.util.spec_from_file_location("nas_tls_reconciler", candidate)
        if spec is None or spec.loader is None:
            break
        module = importlib.util.module_from_spec(spec)
        sys.modules["nas_tls_reconciler"] = module
        spec.loader.exec_module(module)
        return module
    raise RuntimeError("shared NAS TLS reconciler unavailable")


COMMON = _load_common_reconciler()


class _FixedEndpointHTTPSConnection(http.client.HTTPSConnection):
    """Connect to the NAS address while preserving canonical SNI and Host."""

    def __init__(
        self,
        logical_host: str,
        connect_host: str,
        port: int,
        context: ssl.SSLContext,
        timeout: float,
    ) -> None:
        # ``HTTPSConnection`` would otherwise derive its Host header from the
        # IP address.  The DSM virtual host and TLS SNI must remain canonical.
        super().__init__(connect_host, port=port, context=context, timeout=timeout)
        self._logical_host = logical_host
        self._connect_host = connect_host
        self._connect_port = port

    def connect(self) -> None:
        """Open one direct socket and perform TLS with the reviewed SNI."""

        if self._tunnel_host:
            raise OSError("proxy tunnels are not permitted")
        raw_socket: socket.socket | None = None
        try:
            raw_socket = socket.create_connection(
                (self._connect_host, self._connect_port), timeout=self.timeout
            )
            self.sock = self._context.wrap_socket(
                raw_socket, server_hostname=self._logical_host
            )
        except Exception:
            if raw_socket is not None:
                raw_socket.close()
            raise

    def request(
        self,
        method: str,
        url: str,
        body: bytes | str | None = None,
        headers: dict[str, str] | None = None,
        *,
        encode_chunked: bool = False,
    ) -> None:
        """Force the canonical HTTP authority on every DSM request."""

        request_headers = dict(headers or {})
        request_headers["Host"] = self._logical_host
        super().request(
            method,
            url,
            body=body,
            headers=request_headers,
            encode_chunked=encode_chunked,
        )


def _unverified_context() -> ssl.SSLContext:
    """Create the explicit first-import TLS exception context."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    # Python requires hostname checks to be disabled before CERT_NONE can be
    # selected.  The fixed endpoint, canonical SNI, and HTTPS-only transport
    # still apply; no HTTP or redirect fallback exists.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context


class _FixedEndpointClient(COMMON.DsmClient):
    """Use a supplied test route or the production fixed NAS endpoint."""

    def __init__(
        self,
        config: Any,
        *,
        context: ssl.SSLContext,
        connect_host: str = BOOTSTRAP_CONNECT_HOST,
        connect_port: int | None = None,
        socket_factory: Callable[..., socket.socket] | None = None,
    ) -> None:
        super().__init__(
            config,
            connect_host=connect_host,
            socket_factory=socket_factory,
        )
        self.context = context
        self._connect_port = BOOTSTRAP_PORT if connect_port is None else connect_port

    def _connection(self) -> http.client.HTTPSConnection:
        return _FixedEndpointHTTPSConnection(
            BOOTSTRAP_HOSTNAME,
            self.connect_host,
            self._connect_port,
            self.context,
            float(self.config.timeout_seconds),
        )

    def served_fingerprint(self) -> str:
        """Read the served leaf through this client's exact TLS context."""

        raw_socket: socket.socket | None = None
        peer_der: bytes | None = None
        try:
            raw_socket = self.socket_factory(
                (self.connect_host, self._connect_port),
                float(self.config.timeout_seconds),
            )
            raw_socket.settimeout(float(self.config.timeout_seconds))
            with self.context.wrap_socket(
                raw_socket, server_hostname=BOOTSTRAP_HOSTNAME
            ) as tls_socket:
                peer_der = tls_socket.getpeercert(binary_form=True)
        except COMMON.ReconcileError:
            raise
        except (OSError, ssl.SSLError, ValueError):
            COMMON._fail("dsm_tls_verification_failed")
        finally:
            if raw_socket is not None:
                try:
                    raw_socket.close()
                except OSError:
                    pass
        if not peer_der:
            COMMON._fail("dsm_tls_verification_failed")
        return hashlib.sha256(peer_der).hexdigest()


class BootstrapDsmClient(_FixedEndpointClient):
    """Unverified client sealed forever after the one allowed import call."""

    def __init__(
        self,
        config: Any,
        *,
        connect_host: str = BOOTSTRAP_CONNECT_HOST,
        connect_port: int | None = None,
        socket_factory: Callable[..., socket.socket] | None = None,
    ) -> None:
        super().__init__(
            config,
            context=_unverified_context(),
            connect_host=connect_host,
            connect_port=connect_port,
            socket_factory=socket_factory,
        )
        self._sealed = False
        self._import_attempted = False

    def _connection(self) -> http.client.HTTPSConnection:
        if self._sealed:
            COMMON._fail("bootstrap_client_sealed")
        return super()._connection()

    def served_fingerprint(self) -> str:
        """Prevent even a post-seal fingerprint read through the exception client."""

        if self._sealed:
            COMMON._fail("bootstrap_client_sealed")
        return super().served_fingerprint()

    def import_certificate(self, session: Any, target: Any, snapshot: Any) -> None:
        """Permit exactly one import invocation, even when it raises."""

        if self._sealed or self._import_attempted:
            COMMON._fail("bootstrap_client_sealed")
        self._import_attempted = True
        try:
            super().import_certificate(session, target, snapshot)
        finally:
            # Direct callers receive the same one-attempt guarantee as the
            # reviewed wrapper even when the DSM request raises or times out.
            self.seal()

    def logout(self, discovery: Any, session: Any) -> None:
        """Allow logout only for read-only inspect mode before sealing."""

        if self._sealed:
            COMMON._fail("bootstrap_client_sealed")
        super().logout(discovery, session)

    def seal(self) -> None:
        """Make every future bootstrap-client operation fail closed."""

        self._sealed = True


class StrictDsmClient(_FixedEndpointClient):
    """Fresh system-trust client used only after an import attempt."""

    def __init__(
        self,
        config: Any,
        *,
        connect_host: str = BOOTSTRAP_CONNECT_HOST,
        connect_port: int | None = None,
        socket_factory: Callable[..., socket.socket] | None = None,
    ) -> None:
        super().__init__(
            config,
            context=COMMON._client_context(config),
            connect_host=connect_host,
            connect_port=connect_port,
            socket_factory=socket_factory,
        )


def _client(config: Any) -> BootstrapDsmClient:
    """Build the production bootstrap client with no endpoint override."""

    return BootstrapDsmClient(config)


def _strict_client(config: Any) -> StrictDsmClient:
    """Build a new strict client for one post-import verification poll."""

    return StrictDsmClient(config)


def _public_service(service: Any) -> dict[str, Any]:
    """Project one normalized binding to bounded, non-session metadata."""

    if isinstance(service, str):
        return {
            "display_name": "",
            "isPkg": False,
            "owner": "",
            "service": service,
        }
    identity = COMMON._service_identity(service)
    return {
        "display_name": service.get("display_name", ""),
        "isPkg": identity[2],
        "owner": identity[0],
        "service": identity[1],
    }


def _inventory_json(
    certificates: list[Any],
    *,
    private_values: tuple[str, ...] = (),
) -> str:
    """Render public metadata while rejecting reflected credentials/session data."""

    COMMON._inventory_signature(certificates)
    rows = []
    for certificate in sorted(certificates, key=lambda item: item.certificate_id):
        services = sorted(
            (_public_service(service) for service in certificate.services),
            key=lambda item: (item["owner"], item["service"], item["isPkg"]),
        )
        rows.append(
            {
                "description": certificate.description,
                "id": certificate.certificate_id,
                "is_default": certificate.is_default,
                "services": services,
            }
        )
    encoded = json.dumps(
        {"certificates": rows},
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    )
    if len(encoded.encode("utf-8")) > MAX_INVENTORY_OUTPUT_BYTES:
        COMMON._fail("inventory_output_too_large")
    for private_value in private_values:
        if not isinstance(private_value, str) or not private_value:
            continue
        json_escaped = json.dumps(private_value, ensure_ascii=True)
        variants = {
            private_value,
            urllib.parse.quote(private_value, safe=""),
            urllib.parse.quote_plus(private_value),
            json_escaped,
            json_escaped[1:-1],
        }
        if any(candidate and candidate in encoded for candidate in variants):
            # A hostile DSM response must never turn an auth/session value into
            # public Job output, even when it appears in an otherwise-valid
            # certificate description or service display name.
            COMMON._fail("inventory_private_reflection")
    return encoded


def _strict_logout(
    config: Any,
    discovery: Any,
    session: Any,
    *,
    client_factory: Callable[[Any], Any],
) -> None:
    """Best-effort logout through a fresh strict client after import starts."""

    try:
        client = client_factory(config)
        # The original SID/token is sent only through a new system-trust TLS
        # client.  If DSM still presents the old leaf, cleanup fails closed and
        # the process never falls back to an unverified logout.
        client.logout(discovery, session)
    except Exception:
        # Logout is cleanup, so a transport/API failure must not trigger a
        # second import or expose a private response in the Job log.
        pass


def _post_import_verify(
    config: Any,
    snapshot: Any,
    before_inventory: tuple[Any, ...],
    *,
    client_factory: Callable[[Any], Any],
    sleep: Callable[[float], None],
) -> None:
    """Verify the exact inventory and source leaf without another import."""

    last_failure = "post_import_verification_failed"
    for attempt in range(config.retry_count):
        client = client_factory(config)
        discovery = None
        session = None
        try:
            snapshot.assert_stable()
            # Check the new leaf before reading credentials.  A stale or
            # untrusted DSM listener therefore cannot receive a post-import
            # login even if the prior import response was ambiguous.
            if client.served_fingerprint() != snapshot.fingerprint:
                COMMON._fail("served_certificate_mismatch")
            discovery = client.discover()
            username, password = COMMON._read_auth(config)
            session = client.login(discovery, username, password)
            after_certificates = client.list_certificates(session)
            after_inventory = COMMON._inventory_signature(after_certificates)
            if after_inventory != before_inventory:
                COMMON._fail("certificate_inventory_changed")
            snapshot.assert_stable()
            if client.served_fingerprint() != snapshot.fingerprint:
                COMMON._fail("served_certificate_mismatch")
            return
        except COMMON.ReconcileError as error:
            last_failure = error.code
        finally:
            if discovery is not None and session is not None:
                try:
                    # Only this fresh, strict client may log out after the
                    # unverified import attempt.
                    client.logout(discovery, session)
                except COMMON.ReconcileError:
                    pass
        if attempt + 1 < config.retry_count:
            sleep(float(config.retry_delay_seconds))
    COMMON._fail(last_failure)


def bootstrap(
    config: Any,
    *,
    import_once: bool = False,
    client_factory: Callable[[Any], Any] = _client,
    strict_client_factory: Callable[[Any], Any] = _strict_client,
    sleep: Callable[[float], None] = time.sleep,
) -> str:
    """Validate source, inspect inventory, or perform one sealed import."""

    COMMON.validate_config(config)
    snapshot = COMMON.load_source_snapshot(config)
    # This is deliberately before target/auth/API work.  It proves the source
    # key, complete chain, canonical name, validity dates, and lifetime first.
    COMMON.validate_source_snapshot(config, snapshot)
    if import_once:
        # The activation placeholder is rejected before a client or password
        # can be touched; inspect mode intentionally permits it.
        COMMON._validate_target_pin(config)

    client = client_factory(config)
    discovery = None
    session = None
    if not import_once:
        try:
            discovery = client.discover()
            username, password = COMMON._read_auth(config)
            session = client.login(discovery, username, password)
            certificates = client.list_certificates(session)
            return _inventory_json(
                certificates,
                private_values=(username, password, session.sid, session.syno_token),
            )
        finally:
            if discovery is not None and session is not None:
                try:
                    client.logout(discovery, session)
                except COMMON.ReconcileError:
                    pass

    # Import mode never logs out through the unverified client.  Even an auth,
    # timeout, or ambiguous API failure leaves it sealed before strict polling.
    try:
        discovery = client.discover()
        username, password = COMMON._read_auth(config)
        session = client.login(discovery, username, password)
        before_certificates = client.list_certificates(session)
        before_inventory = COMMON._inventory_signature(before_certificates)
        target = COMMON._target_for_import(config, before_certificates)
        snapshot.assert_stable()
        import_attempted = False
        import_error: COMMON.ReconcileError | None = None
        try:
            import_attempted = True
            client.import_certificate(session, target, snapshot)
        except COMMON.ReconcileError as error:
            # DSM may have committed the import before a timeout or error
            # envelope reached this process.  Strict read-back still collects
            # the resulting state, but the original fixed error always makes
            # this one-shot Job fail and can never trigger a retry.
            import_error = COMMON.ReconcileError(error.code)
        finally:
            client.seal()
            if import_attempted:
                _strict_logout(
                    config,
                    discovery,
                    session,
                    client_factory=strict_client_factory,
                )
        post_error: COMMON.ReconcileError | None = None
        try:
            _post_import_verify(
                config,
                snapshot,
                before_inventory,
                client_factory=strict_client_factory,
                sleep=sleep,
            )
        except COMMON.ReconcileError as error:
            post_error = error
        if import_error is not None:
            # An import error is never converted into success by an apparently
            # matching read-back: the DSM mutation outcome remains ambiguous.
            raise import_error
        if post_error is not None:
            raise post_error
        return "imported"
    finally:
        # Deliberately no unverified logout here: the client is sealed forever
        # after import mode starts, including failures before the import call.
        client.seal()


def main(argv: list[str] | None = None) -> int:
    """Emit only bounded inventory JSON or fixed diagnostics."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument(
        "--import-once",
        action="store_true",
        help="Perform exactly one reviewed DSM import, then verify it strictly.",
    )
    args = parser.parse_args(argv)
    try:
        result = bootstrap(
            COMMON.Config.from_file(args.config),
            import_once=args.import_once,
        )
    except COMMON.ReconcileError as error:
        print(f"nas-tls bootstrap failed: {error.code}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, SystemExit):
        raise
    except Exception:
        # Hostile API data, filesystem paths, and credentials must never cross
        # this process boundary as a traceback or interpolated diagnostic.
        print("nas-tls bootstrap failed: internal_error", file=sys.stderr)
        return 1
    if args.import_once:
        print("nas-tls bootstrap: imported")
    else:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
