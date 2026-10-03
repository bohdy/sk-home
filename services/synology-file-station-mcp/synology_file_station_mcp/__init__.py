"""Read-only Synology File Station MCP adapter."""

from .server import build_server, create_adapter

__all__ = ["build_server", "create_adapter"]
