"""Event-log retention sweep.

`event_log` is the server-side durable trail of app-emitted telemetry events
(see `docs/features/telemetry.md`). It accumulates forever unless something
prunes it — at ~hundreds of events per workout plus periodic network pings,
a year of use would grow to tens of millions of rows on a single-user home
server. Not catastrophic, but pointlessly wasteful.

The retention sweep is a single SQL DELETE keyed on `event_log.ts` (the
device-side event timestamp). We prune rows older than a configurable
threshold at startup — no migration, no admin endpoint (Eric's server
isn't exposed to external callers), no cron, no batch worker. One query,
one commit. Idempotent: rerunning with the same threshold is a no-op.

`ts` is the device clock; if Eric's phone is wildly skewed forward, an
event could be pruned earlier than its device-time suggests. Tolerable
for single-user use; if skew ever matters we can key on `received_at`.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from workoutdb_server.models import EventLog


def prune_event_log(db: Session, older_than_days: int) -> int:
    """Delete `event_log` rows whose `ts` is older than `older_than_days`.

    Returns the number of rows deleted. Commits the session so the caller
    doesn't have to. `older_than_days == 0` deletes every row (threshold
    becomes "now"). Negative values are treated as 0 — pruning into the
    future would be nonsensical and we'd rather be defensive than clever.
    """
    days = max(older_than_days, 0)
    cutoff = datetime.now(UTC) - timedelta(days=days)
    # SQLite's DateTime column stores naive datetimes; strip tzinfo so the
    # comparison stays on the same representation the rows were inserted with.
    cutoff_naive = cutoff.replace(tzinfo=None)
    deleted = (
        db.query(EventLog).filter(EventLog.ts < cutoff_naive).delete(synchronize_session=False)
    )
    db.commit()
    return deleted
