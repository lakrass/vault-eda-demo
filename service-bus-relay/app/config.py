"""Configuration utilities for environment variables and URL manipulation.
This module provides helper functions for loading required environment variables
and modifying WebSocket URLs to ensure JSON format is requested.
"""

import os
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode


def env(name: str, default: str | None = None) -> str:
    """Get a required environment variable, raising an error if missing or empty."""
    v = os.getenv(name, default)
    if v is None or v == "":
        raise RuntimeError(f"Missing required env var: {name}")
    return v


def ensure_json_query(ws_url: str) -> str:
    """Ensure the WebSocket URL has 'json=true' in its query parameters."""
    u = urlparse(ws_url)
    q = dict(parse_qsl(u.query, keep_blank_values=True))
    q["json"] = "true"
    new_query = urlencode(q)
    return urlunparse((u.scheme, u.netloc, u.path, u.params, new_query, u.fragment))
