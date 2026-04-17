"""FastAPI dependencies: auth, db session."""

import hmac
from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from workoutdb_server.config import Settings, get_settings
from workoutdb_server.db import make_engine, make_sessionmaker

_bearer = HTTPBearer(auto_error=True)

# Lazy-initialized singletons so tests can swap them via dependency_overrides.
_engine: Engine | None = None
_sessionmaker = None


def _get_engine() -> Engine:
    global _engine, _sessionmaker
    if _engine is None:
        _engine = make_engine()
        _sessionmaker = make_sessionmaker(_engine)
    return _engine


def get_db() -> Iterator[Session]:
    _get_engine()
    assert _sessionmaker is not None
    session = _sessionmaker()
    try:
        yield session
    finally:
        session.close()


def verify_bearer(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    # Timing-safe comparison: never reveal token length or early-match behavior via timing.
    expected = settings.bearer_token.get_secret_value().encode("utf-8")
    provided = credentials.credentials.encode("utf-8")
    if not hmac.compare_digest(expected, provided):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
        )


DbSession = Annotated[Session, Depends(get_db)]
Auth = Depends(verify_bearer)
