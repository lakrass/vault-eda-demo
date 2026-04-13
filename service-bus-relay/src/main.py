"""Main entry point for the service-bus-relay application.
This module orchestrates the Vault event streaming to Azure Service Bus relay service.
It loads environment configuration, sets up health monitoring, and manages the main
async tasks for Vault event processing and Service Bus message sending.
"""

import asyncio
import logging
import signal
import time

from environs import Env

from .health import HealthState, health_server
from .servicebus import ServiceBusSink
from .vault import vault_event_loop

# Constants
HEALTHZ_HOST_DEFAULT = "0.0.0.0"
HEALTHZ_PORT_DEFAULT = 8080
SERVICEBUS_STALE_SECONDS_DEFAULT = 60.0


def load_environment() -> dict:
    """Load and return environment variables."""
    env = Env()
    if env.bool("LOAD_DOTENV", False):
        env.read_env()
    return {
        "vault_addr": env.str("VAULT_ADDR"),
        "vault_azure_role": env.str("VAULT_AZURE_ROLE"),
        "servicebus_connection": env.str("SERVICEBUS_CONNECTION"),
        "servicebus_queue": env.str("SERVICEBUS_QUEUE"),
        "azure_subscription_id": env.str("AZURE_SUBSCRIPTION_ID"),
        "azure_resource_group_name": env.str("AZURE_RESOURCE_GROUP_NAME"),
        "vault_namespace": env.str("VAULT_NAMESPACE", None),
        "vault_event_type": env.str("VAULT_EVENT_TYPE", "kv-v2/data-*"),
        "healthz_host": env.str("HEALTHZ_HOST", HEALTHZ_HOST_DEFAULT),
        "healthz_port": env.int("HEALTHZ_PORT", HEALTHZ_PORT_DEFAULT),
        "servicebus_stale_seconds": env.float(
            "SERVICEBUS_STALE_SECONDS", SERVICEBUS_STALE_SECONDS_DEFAULT
        ),
        "log_level": env.log_level("LOG_LEVEL", logging.INFO),
        "log_format": env.str("LOG_FORMAT", "%(asctime)s [%(levelname)s] %(message)s"),
    }


def install_signals(stop_event, health):
    """Install signal handlers for graceful shutdown."""
    loop = asyncio.get_running_loop()
    shutdown_called = False

    def shutdown():
        nonlocal shutdown_called
        if shutdown_called:
            return
        shutdown_called = True
        health.shutting_down = True
        stop_event.set()  # Signal all tasks to stop

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, shutdown)
        except NotImplementedError:
            # Fallback for platforms without signal handler support (e.g., Windows)
            signal.signal(sig, lambda *_: loop.call_soon_threadsafe(shutdown))


async def main():
    """Main entry point: load config, start health server and worker, handle shutdown."""
    env_vars = load_environment()

    logging.basicConfig(
        level=env_vars["log_level"],
        format=env_vars["log_format"],
    )

    logging.debug(
        "Loaded environment variables: %s", {k: v for k, v in env_vars.items()}
    )

    logging.info(
        "Starting service-bus-relay with Vault addr: %s", env_vars["vault_addr"]
    )

    stop_event = asyncio.Event()
    health = HealthState(started_at=time.monotonic())
    install_signals(stop_event, health)

    # Start health check server
    health_task = asyncio.create_task(
        health_server(
            health,
            env_vars["healthz_host"],
            env_vars["healthz_port"],
            env_vars["servicebus_stale_seconds"],
        )
    )

    # Initialize Service Bus sink and start Vault event loop
    async with ServiceBusSink(
        env_vars["servicebus_connection"],
        env_vars["servicebus_queue"],
        health,
    ) as sink:

        def _log_worker_failure(task: asyncio.Task):
            if task.cancelled():
                return
            exc = task.exception()
            if exc:
                logging.error(
                    "Vault worker failed",
                    exc_info=(type(exc), exc, exc.__traceback__),
                )

        worker = asyncio.create_task(
            vault_event_loop(
                env_vars["vault_addr"],
                env_vars["vault_namespace"],
                env_vars["vault_event_type"],
                env_vars["vault_azure_role"],
                env_vars["azure_subscription_id"],
                env_vars["azure_resource_group_name"],
                stop_event,
                sink,
                health,
            )
        )

        worker.add_done_callback(_log_worker_failure)

        await stop_event.wait()  # Wait for shutdown signal
        worker.cancel()
        health_task.cancel()

        # Gather results, ignoring CancelledError for clean shutdown
        results = await asyncio.gather(worker, health_task, return_exceptions=True)

        errors = [
            r
            for r in results
            if isinstance(r, Exception) and not isinstance(r, asyncio.CancelledError)
        ]

        if errors:
            raise ExceptionGroup("One or more background tasks failed", errors)

    logging.info("Shutdown complete")


if __name__ == "__main__":
    asyncio.run(main())
