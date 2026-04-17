"""User parameters endpoints. Append-only log; latest value is MAX(updated_at) per key.

Caller's user_id is resolved from the bearer token (ADR-2026-04-17).
"""

from datetime import UTC, datetime

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import UserParameterIn, UserParameterRead
from workoutdb_server.models import UserParameter

router = APIRouter(prefix="/api/user-parameters", tags=["user_parameters"])


@router.post("", response_model=list[UserParameterRead])
def append_parameters(
    payload: list[UserParameterIn], db: DbSession, user_id: CurrentUserId
) -> list[UserParameter]:
    """Always inserts. Never updates. That's the contract."""
    inserted: list[UserParameter] = []
    for item in payload:
        row = UserParameter(
            user_id=user_id,
            key=item.key,
            value=item.value,
            updated_at=item.updated_at or datetime.now(UTC),
            source=item.source,
        )
        db.add(row)
        inserted.append(row)
    db.commit()
    for row in inserted:
        db.refresh(row)
    return inserted


@router.get("", response_model=list[UserParameterRead])
def list_parameters(
    db: DbSession,
    user_id: CurrentUserId,
    latest: bool = Query(False, description="If true, return latest-per-key for the user."),
    key: str | None = Query(None, description="Filter to a single key (for history queries)."),
    since: datetime | None = Query(None, description="Return rows with updated_at > since."),
    limit: int = Query(1000, ge=1, le=10000, description="Max rows."),
    offset: int = Query(0, ge=0),
) -> list[UserParameter]:
    """Two query modes combined:

    - `latest=true`: one row per key, the most recent. Used by the app to resolve prescriptions.
    - `key=X` [+ `since=Y`]: full history for a key (Claude's analytical queries).

    Without `latest` or `key`, returns all rows for the user in chronological order.
    """
    if latest:
        subq = (
            select(UserParameter.key, func.max(UserParameter.updated_at).label("ts"))
            .where(UserParameter.user_id == user_id)
            .group_by(UserParameter.key)
            .subquery()
        )
        stmt = (
            select(UserParameter)
            .join(
                subq,
                (UserParameter.key == subq.c.key) & (UserParameter.updated_at == subq.c.ts),
            )
            .where(UserParameter.user_id == user_id)
            .order_by(UserParameter.key)
        )
        return list(db.execute(stmt).scalars().all())

    stmt = select(UserParameter).where(UserParameter.user_id == user_id)
    if key is not None:
        stmt = stmt.where(UserParameter.key == key)
    if since is not None:
        stmt = stmt.where(UserParameter.updated_at > since)
    stmt = stmt.order_by(UserParameter.updated_at).offset(offset).limit(limit)
    return list(db.execute(stmt).scalars().all())
