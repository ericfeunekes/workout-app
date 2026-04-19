"""Pydantic schema helpers — UUID normalization / validation shared base classes.

Unit-level coverage for the `_walk_uuid_fields` helper that powers both
`_UuidReadBase` (lowercase only, DB trusted) and `_UuidInputBase` (lowercase +
UUID format validation). The helper lives at schema-module level, so the tests
exercise the two observable behaviors via concrete subclasses without reaching
into route handlers.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError
from workoutdb_server.api.schemas import _UuidInputBase, _UuidReadBase


class _ReadSample(_UuidReadBase):
    id: str
    workout_id: str
    name: str


class _InputSample(_UuidInputBase):
    id: str
    workout_id: str
    name: str


def test_uuid_fields_lowercase_and_validated():
    """Read path lowercases without format checks; input path lowercases AND validates.

    Both paths share the `_walk_uuid_fields` helper; the boolean `validate`
    flag is the only split. This test covers the four cells of that matrix:

    - read, well-formed UUID: lowercased
    - read, legacy non-UUID (e.g. `ex-0`): lowercased, accepted (DB trusted)
    - input, well-formed UUID: lowercased
    - input, non-UUID: rejected with a `ValueError` translated to 422
    """
    mixed_uuid = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    valid_workout_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    # Read side: lowercase only, no format check.
    read = _ReadSample(id=mixed_uuid, workout_id=valid_workout_id, name="read-case")
    assert read.id == mixed_uuid.lower(), "read must lowercase UUID-shaped ids"
    assert read.workout_id == valid_workout_id

    legacy = _ReadSample(id="ex-0", workout_id=valid_workout_id, name="legacy")
    assert legacy.id == "ex-0", "read side must tolerate non-UUID legacy ids (bug-031)"

    # Non-id/_id fields pass through untouched even if they look UUID-y.
    cased_name = _ReadSample(id=valid_workout_id, workout_id=valid_workout_id, name="FOO-BAR")
    assert cased_name.name == "FOO-BAR"

    # Input side: lowercase + validate.
    input_ok = _InputSample(id=mixed_uuid, workout_id=valid_workout_id, name="input-case")
    assert input_ok.id == mixed_uuid.lower()
    assert input_ok.workout_id == valid_workout_id

    with pytest.raises(ValidationError) as exc_info:
        _InputSample(id="not-a-uuid", workout_id=valid_workout_id, name="bad")
    assert "not a valid UUID" in str(exc_info.value)

    # *_id fields are validated too, not just the `id` primary.
    with pytest.raises(ValidationError) as exc_info:
        _InputSample(id=valid_workout_id, workout_id="still-not-a-uuid", name="bad")
    assert "not a valid UUID" in str(exc_info.value)
