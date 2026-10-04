"""Perform the approved unauthenticated NAS path preflight."""

from __future__ import annotations

import socket
import ssl
from typing import Any


NAS_ADDRESS = "10.1.100.10"
NAS_PORT = 5001
CANONICAL_HOSTNAME = "nas.bohdy.sk"
CONNECT_TIMEOUT_SECONDS = 10.0
PASSED_MESSAGE = "nas-tls path preflight: passed"
FAILED_MESSAGE = "nas-tls path preflight: failed"


def _tls_context() -> ssl.SSLContext:
    """Build the fixed transport context for reachability only."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    # This phase ignores the current DSM leaf for reachability. Strict source
    # validation precedes the later unverified inspection/import; strict served-
    # leaf verification begins after import and for recurring delivery.
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def _close_quietly(connection: Any) -> None:
    """Close a transport without exposing cleanup details in Job output."""

    if connection is None:
        return
    try:
        connection.close()
    except Exception:
        return


def run_preflight() -> bool:
    """Make one bounded TLS connection to the fixed NAS endpoint."""

    raw_socket = None
    tls_socket = None
    try:
        raw_socket = socket.create_connection(
            (NAS_ADDRESS, NAS_PORT),
            timeout=CONNECT_TIMEOUT_SECONDS,
        )
        tls_socket = _tls_context().wrap_socket(
            raw_socket,
            server_hostname=CANONICAL_HOSTNAME,
            do_handshake_on_connect=True,
        )
        return True
    except (OSError, ssl.SSLError, TimeoutError):
        return False
    except Exception:
        return False
    finally:
        _close_quietly(tls_socket if tls_socket is not None else raw_socket)


def main() -> int:
    """Emit one stable result and no transport or exception details."""

    passed = run_preflight()
    print(PASSED_MESSAGE if passed else FAILED_MESSAGE)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
