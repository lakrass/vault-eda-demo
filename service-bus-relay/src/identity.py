"""Azure identity and token management utilities.
This module provides functions for acquiring Azure tokens using DefaultAzureCredential,
which supports various authentication methods including managed identity, Azure CLI login,
and service principal credentials. It also includes JWT token validation utilities.
"""

from __future__ import annotations

import asyncio
import json
import base64
import time
import logging
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.core.exceptions import AzureError

# Constants
DEFAULT_RESOURCE = "https://management.azure.com/.default"
LEEWAY_SECONDS_DEFAULT = 30


def _decode_jwt_payload(token: str) -> dict:
    """Decode and return the JWT payload from the token string."""
    payload_b64 = token.split(".")[1]
    payload_b64 += "=" * (-len(payload_b64) % 4)  # Fix missing base64 padding
    return json.loads(base64.urlsafe_b64decode(payload_b64).decode("utf-8"))


def get_azure_token(
    resource: str = DEFAULT_RESOURCE, client_id: Optional[str] = None
) -> str:
    """Acquire an Azure token using DefaultAzureCredential (supports managed identity, az login,
    etc.)."""
    try:
        credential = (
            DefaultAzureCredential(managed_identity_client_id=client_id)
            if client_id
            else DefaultAzureCredential()
        )
        token = credential.get_token(resource)
        logging.debug(
            "Acquired Azure token (expires in %ds)",
            token.expires_on - int(time.time()),
        )
        return token.token
    except AzureError as exc:
        logging.error("Failed to acquire Azure token: %s", exc)
        raise RuntimeError("Failed to acquire Azure token") from exc


async def get_azure_token_async(
    resource: str = DEFAULT_RESOURCE, client_id: Optional[str] = None
) -> str:
    """Async wrapper for Azure token acquisition."""
    return await asyncio.to_thread(get_azure_token, resource, client_id)


def is_token_expired(token: str, leeway_seconds: int = LEEWAY_SECONDS_DEFAULT) -> bool:
    """Check if the JWT token is expired, with optional leeway."""
    try:
        payload = _decode_jwt_payload(token)
        exp = payload.get("exp")
        if exp is None:
            return True  # No expiry means consider expired
        now = int(time.time())
        expired = now >= (int(exp) - leeway_seconds)
        if expired:
            logging.debug("Token is expired")
        return expired
    except (ValueError, json.JSONDecodeError, KeyError) as e:
        logging.warning("Failed to check token expiry: %s", e)
        return True  # On error, assume expired
