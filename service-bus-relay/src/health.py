"""Health monitoring and HTTP server utilities.
This module provides a simple HTTP health check server that reports the readiness
and liveness status of the service-bus-relay application. It tracks the health state
of Vault connections and Service Bus operations, and serves health endpoints for
Kubernetes readiness and liveness probes.
"""

import asyncio
import json
import time
import logging

from dataclasses import dataclass

# Constants
BUFFER_SIZE_MAX = 4096
READ_TIMEOUT = 1.0
CONTENT_TYPE_JSON = "application/json"
CONNECTION_CLOSE = "close"


@dataclass
class HealthState:
    """Tracks the overall health state of the service-bus-relay application.
    This dataclass maintains flags and timestamps for Vault connectivity,
    Service Bus readiness, and recent send operation results.
    """

    started_at: float
    shutting_down: bool = False

    vault_connected: bool = False
    vault_last_error: str = ""

    sb_ready: bool = False
    sb_last_error: str = ""
    sb_last_send_ok_at: float = 0.0
    sb_last_send_err_at: float = 0.0

    def now(self) -> float:
        """Get the current monotonic time for health calculations."""
        return time.monotonic()

    def readiness_ok(self, sb_stale_after: float) -> bool:
        """Check if the service is ready: not shutting down, both services connected, and no recent
        send failures."""
        if self.shutting_down:
            return False
        if not self.vault_connected or not self.sb_ready:
            return False
        # If last send failed and it's been stale for too long, consider not ready
        if self.sb_last_send_err_at > self.sb_last_send_ok_at:
            if self.now() - self.sb_last_send_err_at >= sb_stale_after:
                return False
        return True


@dataclass
class HealthResponse:
    """Represents an HTTP response for health check endpoints.
    Contains the status code and JSON body for health check responses.
    """

    code: int
    body: dict

    def to_bytes(self) -> bytes:
        """Serialize the response to HTTP bytes for transmission."""
        body_bytes = json.dumps(self.body).encode()
        reason = {200: "OK", 503: "Service Unavailable", 404: "Not Found"}[self.code]
        return (
            f"HTTP/1.1 {self.code} {reason}\r\n"
            f"Content-Type: {CONTENT_TYPE_JSON}\r\n"
            f"Content-Length: {len(body_bytes)}\r\n"
            f"Connection: {CONNECTION_CLOSE}\r\n\r\n"
        ).encode() + body_bytes


async def _read_request_path(reader: asyncio.StreamReader) -> str:
    """Read and parse the request path from the HTTP request, with timeout and size limits."""
    buffer = bytearray()
    while b"\r\n\r\n" not in buffer and len(buffer) < BUFFER_SIZE_MAX:
        try:
            chunk = await asyncio.wait_for(reader.read(1024), timeout=READ_TIMEOUT)
        except asyncio.TimeoutError:
            break
        if not chunk:
            break
        buffer.extend(chunk)

    req = buffer.decode("utf-8", errors="ignore")
    first_line = req.splitlines()[0] if req else ""
    parts = first_line.split()
    if len(parts) >= 2 and parts[0] == "GET":
        return parts[1]
    return "/"


async def handle_health(reader, writer, health: HealthState, sb_stale_after: float):
    """Handle incoming health check requests."""
    path = await _read_request_path(reader)

    if path in ("/healthz", "/livez"):
        response = HealthResponse(
            200,
            {"status": "alive", "uptime": round(health.now() - health.started_at, 2)},
        )
    elif path == "/readyz":
        ready = health.readiness_ok(sb_stale_after)
        response = HealthResponse(
            200 if ready else 503,
            {
                "status": "ready" if ready else "not_ready",
                "vault_connected": health.vault_connected,
                "servicebus_ready": health.sb_ready,
                "vault_error": health.vault_last_error,
                "servicebus_error": health.sb_last_error,
            },
        )
    else:
        response = HealthResponse(404, {})

    logging.debug(
        "Health check: %s -> %s", path, response.body.get("status", "unknown")
    )
    writer.write(response.to_bytes())
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def health_server(
    health: HealthState, host: str, port: int, sb_stale_after: float
):
    """Start the health check server."""
    server = await asyncio.start_server(
        lambda r, w: handle_health(r, w, health, sb_stale_after),
        host,
        port,
    )
    async with server:
        await server.serve_forever()
