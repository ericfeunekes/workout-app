"""User parameters endpoints. Append-only log; latest value is MAX(updated_at) per key.

Caller's user_id is resolved from the bearer token (ADR-2026-04-17).
"""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import func, select

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import UserParameterIn, UserParameterRead
from workoutdb_server.models import UserParameter

router = APIRouter(prefix="/api/user-parameters", tags=["user_parameters"])


@router.post("", response_model=list[UserParameterRead])
def append_parameters(
    payload: list[UserParameterIn], db: DbSession, user_id: CurrentUserId
) -> list[UserParameter]:
    """Insert-or-upsert per row.

    The append-only contract is on (user_id, key) — multiple rows for the same
    key over time is the design. Idempotency is on PK: when the caller supplies
    an `id`, a replay of the same payload UPSERTS on that id rather than
    inserting a second row. This keeps app-side retries safe — the iOS push
    queue may replay a commit after a crash-between-commit-and-queue-remove,
    and without id-level idempotency that replay would double-write the row
    (and since append-only reads never delete, the duplicate would live
    forever). When `id` is omitted (Claude's bulk imports), the server
    generates a fresh UUID via the ORM default.
    """
    committed: list[UserParameter] = []
    for item in payload:
        updated_at = item.updated_at or datetime.now(UTC)
        if item.id is not None:
            existing = db.get(UserParameter, item.id)
            if existing is not None:
                # Tenant guard: the deterministic id scheme lives in the
                # app (hash of userID+key+timestamp) so collisions across
                # users are astronomically unlikely, but a malicious or
                # misbehaving client could replay another user's UUID to
                # try to read its row. Refuse with 403 instead of
                # returning the sibling-tenant's value.
                if existing.user_id != user_id:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail=f"user_parameter {item.id} belongs to another user",
                    )
                # Row already exists for this deterministic id — treat the
                # second push as a no-op update so the response still
                # carries the canonical row (value + updated_at from the
                # original commit). Writing EXCLUDED.value here would let
                # a racing second call overwrite the first's value; the
                # deterministic id guarantees the caller is re-sending
                # the same logical row, so keeping the first write wins
                # by construction.
                committed.append(existing)
                continue
            row = UserParameter(
                id=item.id,
                user_id=user_id,
                key=item.key,
                value=item.value,
                updated_at=updated_at,
                source=item.source,
            )
        else:
            row = UserParameter(
                user_id=user_id,
                key=item.key,
                value=item.value,
                updated_at=updated_at,
                source=item.source,
            )
        db.add(row)
        committed.append(row)
    db.commit()
    for row in committed:
        db.refresh(row)
    return committed


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
