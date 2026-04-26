#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "azure-monitor-opentelemetry>=1.6.0",
#     "opentelemetry-instrumentation-fastapi>=0.46b0",
#     "opentelemetry-instrumentation-asyncpg>=0.46b0",
#     "opentelemetry-instrumentation-httpx>=0.46b0",
# ]
# ///
"""
Initialize OpenTelemetry tracing for FastAPI with Azure Monitor.

Usage:
    # As a module import
    from init_tracing import configure_tracing
    configure_tracing(app)

    # Or run standalone to verify configuration
    uv run init_tracing.py --check
"""

import os
import sys
from typing import Optional

from opentelemetry import trace


def configure_tracing(
    app=None,
    service_name: str = "fastapi-service",
    service_version: str = "0.0.0",
    connection_string: Optional[str] = None,
    sampling_ratio: float = 1.0,
    excluded_urls: str = "health,ready,metrics",
    instrument_db: bool = True,
    instrument_httpx: bool = True,
) -> None:
    """
    Configure OpenTelemetry tracing with Azure Monitor.

    Args:
        app: FastAPI application instance (optional, can instrument later)
        service_name: Name of the service for telemetry
        service_version: Version of the service
        connection_string: Azure Monitor connection string (or use env var)
        sampling_ratio: Sampling ratio (1.0 = 100%, 0.1 = 10%)
        excluded_urls: Comma-separated URL patterns to exclude from tracing
        instrument_db: Whether to instrument asyncpg
        instrument_httpx: Whether to instrument httpx client
    """
    from azure.monitor.opentelemetry import configure_azure_monitor
    from opentelemetry.sdk.resources import SERVICE_NAME, SERVICE_VERSION, Resource

    # Get connection string from arg or environment
    conn_str = connection_string or os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if not conn_str:
        raise ValueError(
            "Azure Monitor connection string required. "
            "Set APPLICATIONINSIGHTS_CONNECTION_STRING or pass connection_string parameter."
        )

    # Create resource with service info
    resource = Resource.create(
        {
            SERVICE_NAME: service_name,
            SERVICE_VERSION: service_version,
            "deployment.environment": os.environ.get("ENVIRONMENT", "development"),
        }
    )

    # Configure Azure Monitor
    configure_azure_monitor(
        connection_string=conn_str,
        resource=resource,
        sampling_ratio=sampling_ratio,
        logger_name=service_name,
    )

    # Instrument FastAPI if app provided
    if app is not None:
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

        FastAPIInstrumentor.instrument_app(
            app,
            excluded_urls=excluded_urls,
        )

    # Instrument database
    if instrument_db:
        try:
            from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor

            AsyncPGInstrumentor().instrument()
        except ImportError:
            pass  # asyncpg not installed

    # Instrument HTTP client
    if instrument_httpx:
        try:
            from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

            HTTPXClientInstrumentor().instrument()
        except ImportError:
            pass  # httpx not installed


def get_tracer(name: str = __name__):
    """Get a tracer instance for manual instrumentation."""
    return trace.get_tracer(name)


def check_configuration() -> bool:
    """Verify Azure Monitor configuration is valid."""
    conn_str = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")

    if not conn_str:
        print("❌ APPLICATIONINSIGHTS_CONNECTION_STRING not set")
        return False

    # Parse connection string
    parts = dict(part.split("=", 1) for part in conn_str.split(";") if "=" in part)

    if "InstrumentationKey" not in parts:
        print("❌ Connection string missing InstrumentationKey")
        return False

    if "IngestionEndpoint" not in parts:
        print("❌ Connection string missing IngestionEndpoint")
        return False

    print("✓ Connection string valid")
    print(f"  Instrumentation Key: {parts['InstrumentationKey'][:8]}...")
    print(f"  Ingestion Endpoint: {parts['IngestionEndpoint']}")

    # Check optional dependencies
    dependencies = [
        ("opentelemetry.instrumentation.fastapi", "FastAPI"),
        ("opentelemetry.instrumentation.asyncpg", "asyncpg"),
        ("opentelemetry.instrumentation.httpx", "httpx"),
    ]

    print("\nInstrumentation libraries:")
    for module, name in dependencies:
        try:
            __import__(module)
            print(f"  ✓ {name}")
        except ImportError:
            print(f"  ○ {name} (not installed)")

    return True


if __name__ == "__main__":
    if "--check" in sys.argv:
        success = check_configuration()
        sys.exit(0 if success else 1)
    else:
        print(__doc__)
