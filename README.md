# WorkoutDB

Local-first workout planning/logging system (SQLite + CLI).

## Quickstart

```bash
uv venv
uv pip install -e .
workoutdb --help
```

## Google Calendar (optional)

Create a config file (default `~/.workout-app/config.toml`):

```toml
[paths]
app_home = "/Users/ericfeunekes/.workout-app"

[google]
client_secret_path = "/Users/ericfeunekes/.workout-app/google-client.json"

[calendar]
default_id = "primary"
```

Then list calendars and push timed workouts:

```bash
workoutdb plan calendar list
workoutdb plan push-calendar --db path/to/workout.db --user "Name" --no-dry-run
```

Planned workouts must include `start_time` and `duration_min` to be pushed.

## Testing

See `docs/testing-pyramid.md` for the full testing structure and how to run it.

## Data model

See `docs/data-model/README.md` for the current model overview.
