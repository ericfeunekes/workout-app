"""Contract test: committed schema/openapi.json matches what FastAPI currently produces.

Fails on drift so any API change must regenerate + commit the schema (see schema/README.md).
"""

import json
from pathlib import Path

import pytest

_SCHEMA_PATH = Path(__file__).resolve().parents[2] / "schema" / "openapi.json"


@pytest.fixture
def live_openapi(monkeypatch: pytest.MonkeyPatch) -> dict:
    # Settings loading requires these; using dummies is safe because we never
    # hit the DB or check the bearer token — we only introspect the app's schema.
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", "dummy")
    monkeypatch.setenv("WORKOUTDB_DB_PATH", "/tmp/dummy.db")
    from workoutdb_server.config import get_settings

    get_settings.cache_clear()

    from workoutdb_server.main import app

    return app.openapi()


def test_openapi_committed_matches_live(live_openapi: dict) -> None:
    assert _SCHEMA_PATH.exists(), (
        f"{_SCHEMA_PATH} missing — run the regen command in schema/README.md"
    )

    committed = json.loads(_SCHEMA_PATH.read_text())
    if committed != live_openapi:
        # Provide a actionable failure message.
        regen_cmd = (
            "WORKOUTDB_BEARER_TOKEN=dummy WORKOUTDB_DB_PATH=/tmp/dummy.db "
            'uv run python -c "import json; from workoutdb_server.main import app; '
            'print(json.dumps(app.openapi(), indent=2))" > schema/openapi.json'
        )
        pytest.fail(
            "schema/openapi.json is stale — API changed without regenerating the schema. "
            f"Regenerate with:\n  {regen_cmd}"
        )


def test_openapi_has_all_expected_paths(live_openapi: dict) -> None:
    paths = set(live_openapi.get("paths", {}).keys())
    expected = {
        "/health",
        "/api/version",
        "/api/exercises",
        "/api/user-parameters",
        "/api/workouts",
        "/api/workouts/{workout_id}",
        "/api/sync/pull",
        "/api/sync/results",
    }
    missing = expected - paths
    assert not missing, f"Missing endpoints in OpenAPI: {missing}"


def test_openapi_requires_bearer_auth(live_openapi: dict) -> None:
    # Most endpoints should reference the HTTPBearer security scheme.
    schemes = live_openapi.get("components", {}).get("securitySchemes", {})
    assert schemes, "No securitySchemes declared; bearer auth isn't surfaced in the OpenAPI"
    bearer = any(s.get("type") == "http" and s.get("scheme") == "bearer" for s in schemes.values())
    assert bearer, f"HTTP Bearer scheme not found in securitySchemes: {list(schemes)}"


def test_sync_results_response_schema_is_specific(live_openapi: dict) -> None:
    response = live_openapi["paths"]["/api/sync/results"]["post"]["responses"]["200"]
    schema_ref = response["content"]["application/json"]["schema"]["$ref"]
    assert schema_ref == "#/components/schemas/SyncResultsOut"

    schema = live_openapi["components"]["schemas"]["SyncResultsOut"]
    assert set(schema["required"]) == {
        "primitive_set_logs_received",
        "status_updates_received",
        "workout_resets_received",
    }
