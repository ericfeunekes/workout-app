"""Logging setup + request-id middleware.

JSON-structured logs in prod (easier to grep; works for a future log aggregator).
Plain format in debug mode. Request IDs are generated per-request and attached to
every log line emitted during request handling via contextvar.
"""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid
from contextvars import ContextVar

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

_request_id_var: ContextVar[str | None] = ContextVar("workoutdb_request_id", default=None)


def current_request_id() -> str | None:
    return _request_id_var.get()


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        rid = _request_id_var.get()
        if rid:
            payload["request_id"] = rid
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        for key, value in record.__dict__.items():
            if key in ("args", "msg", "levelname", "name", "exc_info", "exc_text"):
                continue
            if key.startswith("_") or key in payload:
                continue
            if key in (
                "msecs",
                "relativeCreated",
                "created",
                "thread",
                "threadName",
                "process",
                "processName",
                "pathname",
                "filename",
                "module",
                "lineno",
                "funcName",
                "levelno",
                "stack_info",
            ):
                continue
            payload[key] = value
        return json.dumps(payload, default=str)


def configure_logging(*, debug: bool) -> None:
    """Idempotent — safe to call multiple times (e.g., tests)."""
    root = logging.getLogger()
    for handler in list(root.handlers):
        root.removeHandler(handler)

    handler = logging.StreamHandler(sys.stdout)
    if debug:
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s - %(message)s"))
    else:
        handler.setFormatter(_JsonFormatter())

    root.addHandler(handler)
    root.setLevel(logging.DEBUG if debug else logging.INFO)


class RequestIdMiddleware(BaseHTTPMiddleware):
    """Generates a request ID (or reuses `X-Request-ID` if the caller provided one)
    and logs request start/end with duration."""

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)
        self._logger = logging.getLogger("workoutdb_server.request")

    async def dispatch(self, request: Request, call_next):
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:16]
        token = _request_id_var.set(rid)
        started = time.monotonic()
        try:
            response: Response = await call_next(request)
        except Exception:
            duration_ms = (time.monotonic() - started) * 1000
            self._logger.exception(
                "request failed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": round(duration_ms, 1),
                },
            )
            raise
        finally:
            _request_id_var.reset(token)

        duration_ms = (time.monotonic() - started) * 1000
        self._logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round(duration_ms, 1),
            },
        )
        response.headers["X-Request-ID"] = rid
        return response
