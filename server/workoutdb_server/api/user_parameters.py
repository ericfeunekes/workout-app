"""User parameters endpoints. Append-only log; latest value is MAX(updated_at) per key."""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import func, select

from workoutdb_server.api.deps import Auth, DbSession
from workoutdb_server.api.schemas import UserParameterIn, UserParameterRead
from workoutdb_server.models import AppUser, UserParameter

router = APIRouter(prefix="/api/user-parameters", tags=["user_parameters"])


@router.post("", response_model=list[UserParameterRead], dependencies=[Auth])
def append_parameters(payload: list[UserParameterIn], db: DbSession) -> list[UserParameter]:
    """Always inserts. Never updates. That's the contract."""
    # Validate all referenced users up front so the whole batch is atomic.
    unknown = {item.user_id for item in payload if db.get(AppUser, item.user_id) is None}
    if unknown:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown user_id(s): {sorted(unknown)}",
        )

    inserted: list[UserParameter] = []
    for item in payload:
        row = UserParameter(
            user_id=item.user_id,
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


@router.get("", response_model=list[UserParameterRead], dependencies=[Auth])
def list_parameters(
    db: DbSession,
    user_id: str = Query(..., description="Required — scopes the query to one user."),
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
