# Testing Pyramid

Goal: validate correctness with fast unit tests, validate DB + IO workflows with integration tests, and keep a small smoke layer that proves the CLI starts.

## Unit (fast, pure)
- Scope: validators, parsing, pure helpers.
- Locations: `tests/unit/`
- Examples:
  - YAML model validation (pairing start_time + duration).
  - SQL statement parser.
  - Calendar event payload construction.
  - Contract checks against the Google Calendar VCR cassette.

## Integration (DB + IO)
- Scope: SQLite migrations, YAML import, plan generation behavior.
- Locations: `tests/integration/`
- Examples:
  - Import YAML -> planned_workout stores start_time/duration.
  - Plan generation preserves existing times when rescheduling.

## Smoke (CLI wiring)
- Scope: CLI boots and basic command surfaces respond.
- Locations: `tests/smoke/`
- Examples:
  - `workoutdb --help` responds.

## Running tests
```bash
uv pip install -e ".[dev]"
pytest
```
