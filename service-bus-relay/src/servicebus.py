"""Azure Service Bus message sending utilities.
This module provides an async-safe context manager for sending JSON messages
to Azure Service Bus queues. It integrates with the health monitoring system
to track send operation success and failures.
"""

import asyncio
import json
import uuid
import logging

from azure.servicebus import ServiceBusClient, ServiceBusMessage
from .health import HealthState

# Constants
CONTENT_TYPE_JSON = "application/json"


def safe_extract_id(payload: str) -> str:
    """Safely extract an ID from JSON payload or generate a UUID."""
    try:
        obj = json.loads(payload)
        if isinstance(obj, dict) and obj.get("id"):
            return str(obj["id"])
    except json.JSONDecodeError:
        pass
    return str(uuid.uuid4())


class ServiceBusSink:
    """Async context manager for sending messages to Azure Service Bus."""

    def __init__(self, conn_str: str, queue: str, health: HealthState):
        self.conn_str = conn_str
        self.queue = queue
        self.health = health
        self.client = None
        self.sender = None

    async def __aenter__(self):
        """Initialize the Service Bus client and sender asynchronously."""
        self.client = ServiceBusClient.from_connection_string(self.conn_str)
        self.sender = self.client.get_queue_sender(self.queue)

        try:
            # Enter the sender context in a thread to avoid blocking
            await asyncio.to_thread(self.sender.__enter__)
        except Exception:
            # Clean up on failure
            self.client.close()
            self.client = None
            self.sender = None
            raise

        self.health.sb_ready = True
        return self

    async def __aexit__(self, *_):
        """Clean up the sender and client asynchronously."""
        if self.sender:
            await asyncio.to_thread(self.sender.__exit__, None, None, None)
            self.sender = None
        if self.client:
            await asyncio.to_thread(self.client.close)
            self.client = None
        self.health.sb_ready = False

    def _create_message(self, payload: str) -> ServiceBusMessage:
        """Create a Service Bus message from payload."""
        return ServiceBusMessage(
            body=payload,
            message_id=safe_extract_id(payload),
            content_type=CONTENT_TYPE_JSON,
        )

    async def send(self, payload: str):
        """Send a message to the Service Bus queue."""
        if self.sender is None:
            raise RuntimeError("ServiceBusSink is not initialized")

        msg = self._create_message(payload)

        try:
            await asyncio.to_thread(self.sender.send_messages, msg)
            self.health.sb_last_send_ok_at = self.health.now()
            self.health.sb_last_error = ""
            logging.debug(
                "Sent message to Service Bus queue: %s (ID: %s)",
                self.queue,
                msg.message_id,
            )
        except Exception as e:
            self.health.sb_last_send_err_at = self.health.now()
            self.health.sb_last_error = str(e)
            logging.error("Failed to send message to Service Bus: %s", e)
            raise
