"""Database layer. SQLAlchemy engine and session management.

Data layer — may depend on config; must not depend on api or sync.
"""

from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from workoutdb_server.config import Settings, get_settings


def make_engine(settings: Settings | None = None) -> Engine:
    """Build an engine from settings. Explicit arg lets tests inject an in-memory DB."""
    settings = settings or get_settings()
    engine = create_engine(
        f"sqlite:///{settings.db_path}",
        echo=settings.debug,
        future=True,
    )
    # SQLite doesn't enforce foreign keys by default — enable per-connection.
    event.listen(engine, "connect", _enable_foreign_keys)
    return engine


def _enable_foreign_keys(dbapi_connection, _connection_record) -> None:
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def make_sessionmaker(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@contextmanager
def session_scope(engine: Engine) -> Iterator[Session]:
    """Context manager: commits on success, rolls back on error, always closes."""
    session = make_sessionmaker(engine)()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
