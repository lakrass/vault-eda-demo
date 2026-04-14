"""Vault event streaming and authentication utilities.
This module handles WebSocket connections to HashiCorp Vault for event streaming,
Azure authentication with Vault, and relaying events to Azure Service Bus.
It includes exponential backoff for connection resilience and health state tracking.
"""

# app/vault.py

import asyncio
import logging
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode

import hvac
import websockets

from .health import HealthState
from .servicebus import ServiceBusSink
from .identity import get_azure_token_async, is_token_expired

# Constants
BACKOFF_INITIAL = 1.0
BACKOFF_MAX = 30.0
BACKOFF_MULTIPLIER = 2.0
AUTH_STATUS_CODES = (401, 403)


def build_url(vault_addr: str, vault_event_type: str) -> str:
    """Build the WebSocket URL for Vault event subscription."""
    u = urlparse(vault_addr)
    u.scheme = "wss" if u.scheme == "https" else "ws"
    u.path = f"/v1/sys/events/subscribe/{vault_event_type}"

    q = dict(parse_qsl(u.query, keep_blank_values=True))
    q["json"] = "true"

    new_query = urlencode(q)
    return urlunparse((u.scheme, u.netloc, u.path, u.params, new_query, u.fragment))


def login_via_azure_auth(
    vault_addr: str, vault_namespace: str, vault_azure_role: str, azure_jwt: str
) -> hvac.Client:
    """Authenticate with Vault using Azure JWT."""
    client = hvac.Client(
        url=vault_addr,
        namespace=vault_namespace,
    )

    client.auth.azure.login(
        role=vault_azure_role,
        jwt=azure_jwt,
    )

    if not client.is_authenticated():
        raise RuntimeError("Vault Azure authentication failed")

    return client


async def login_via_azure_auth_async(
    vault_addr: str, vault_namespace: str, vault_azure_role: str, azure_jwt: str
) -> hvac.Client:
    """Async wrapper for Vault Azure authentication."""
    return await asyncio.to_thread(
        login_via_azure_auth, vault_addr, vault_namespace, vault_azure_role, azure_jwt
    )


async def _connect_and_stream(
    ws_url: str,
    headers: dict,
    stop_event: asyncio.Event,
    sink: ServiceBusSink,
    health: HealthState,
):
    """Connect to Vault WS and stream messages."""
    async with websockets.connect(ws_url, additional_headers=headers) as ws:
        logging.info("Connected to Vault event stream")
        health.vault_connected = True
        health.vault_last_error = ""

        async for message in ws:
            if stop_event.is_set():
                break
            logging.debug("Processing Vault event: %s", message[:100])
            await sink.send(message)


async def vault_event_loop(
    vault_addr: str,
    vault_namespace: str,
    vault_event_type: str,
    vault_azure_role: str,
    azure_client_id: str | None,
    stop_event: asyncio.Event,
    sink: ServiceBusSink,
    health: HealthState,
):
    """Main event loop for Vault WebSocket connection and message relay."""
    ws_url = build_url(vault_addr, vault_event_type)

    headers = {}
    if vault_namespace:
        headers["X-Vault-Namespace"] = vault_namespace

    logging.info("Initializing connection to Vault")
    azure_jwt = await get_azure_token_async(client_id=azure_client_id)
    vault_client = await login_via_azure_auth_async(
        vault_addr, vault_namespace, vault_azure_role, azure_jwt
    )

    backoff = BACKOFF_INITIAL

    while not stop_event.is_set():
        try:
            logging.info("Connecting to Vault events WS: %s", ws_url)
            headers["X-Vault-Token"] = vault_client.token

            await _connect_and_stream(ws_url, headers, stop_event, sink, health)
            backoff = BACKOFF_INITIAL  # Reset on success

        except asyncio.CancelledError:
            logging.info("Vault loop cancelled, shutting down")
            raise

        except websockets.exceptions.InvalidStatus as e:
            status = getattr(e, "status_code", None)
            health.vault_connected = False
            health.vault_last_error = str(e)

            if status in AUTH_STATUS_CODES:
                logging.warning(
                    "Vault WS rejected connection with %s, re-authenticating...", status
                )
                try:
                    if is_token_expired(azure_jwt):
                        logging.info("Token expired, refreshing...")
                        azure_jwt = await get_azure_token_async(
                            client_id=azure_client_id
                        )
                    vault_client = await login_via_azure_auth_async(
                        vault_addr, vault_namespace, vault_azure_role, azure_jwt
                    )
                    logging.info("Vault re-authentication successful")
                except RuntimeError as auth_err:
                    logging.exception("Vault re-authentication failed: %s", auth_err)
            else:
                logging.warning(
                    "Vault WS handshake failed with %s (no re-auth attempted)", status
                )

        except (websockets.WebSocketException, ConnectionError, OSError) as e:
            health.vault_connected = False
            health.vault_last_error = str(e)
            logging.exception("Vault WS connection error, reconnecting")

        except Exception as e:  # pylint: disable=broad-except
            health.vault_connected = False
            health.vault_last_error = str(e)
            logging.exception("Unexpected Vault WS error, reconnecting")

        finally:
            health.vault_connected = False

        logging.info("Reconnecting in %.1fs", backoff)
        await asyncio.sleep(backoff)
        backoff = min(backoff * BACKOFF_MULTIPLIER, BACKOFF_MAX)

    health.vault_connected = False
    logging.info("Vault event loop stopped")
