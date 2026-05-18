from __future__ import annotations

import json
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
INTEGRATION_DIR = Path(__file__).resolve().parent
TOKEN = "integration-token-123456"
USER_ID = "11111111-1111-4111-8111-111111111111"
WORKOUT_ID = "22222222-2222-4222-8222-222222222222"
EXERCISE_ID = "33333333-3333-4333-8333-333333333333"
BLOCK_ID = "44444444-4444-4444-8444-444444444444"
SET_ID = "55555555-5555-4555-8555-555555555555"
SLOT_ID = "66666666-6666-4666-8666-666666666666"
SET_LOG_ID = "77777777-7777-4777-8777-777777777777"


def test_swift_sync_probe_round_trips_primitives_over_real_http(tmp_path: Path) -> None:
    if shutil.which("swift") is None:
        pytest.fail("swift is required for the real HTTP sync probe")

    db_path = tmp_path / "workoutdb.sqlite"
    with bound_server_socket() as (server_socket, port):
        env = server_env(db_path)
        process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "workoutdb_server.main:app",
                "--fd",
                str(server_socket.fileno()),
                "--log-level",
                "warning",
            ],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            pass_fds=(server_socket.fileno(),),
        )
        try:
            base_url = f"http://127.0.0.1:{port}"
            wait_for_ready(base_url, process)
            seed_server(base_url)
            run_swift_probe(base_url)
            assert_primitive_set_log_upserted(db_path)
        finally:
            process.terminate()
            try:
                process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=10)


def server_env(db_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "WORKOUTDB_BEARER_TOKEN": TOKEN,
            "WORKOUTDB_USER_ID": USER_ID,
            "WORKOUTDB_USER_NAME": "Integration Probe",
            "WORKOUTDB_DB_PATH": str(db_path),
        }
    )
    return env


def wait_for_ready(base_url: str, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 20
    url = f"{base_url}/health/ready"
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"server exited early\nstdout:\n{stdout}\nstderr:\n{stderr}")
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError):
            time.sleep(0.1)
    raise AssertionError("server did not become ready")


def seed_server(base_url: str) -> None:
    post_json(
        f"{base_url}/api/exercises",
        [
            {
                "id": EXERCISE_ID,
                "name": "Probe squat",
                "category": "strength",
            }
        ],
    )
    post_json(
        f"{base_url}/api/workouts",
        {
            "id": WORKOUT_ID,
            "name": "Real HTTP primitive probe",
            "scheduled_date": "2026-05-18",
            "status": "planned",
            "source": "claude",
            "primitive_blocks": [primitive_block()],
        },
    )


def primitive_block() -> dict[str, object]:
    return {
        "id": BLOCK_ID,
        "title": "Probe block",
        "repeat": 1,
        "work_target": [],
        "sets": [
            {
                "id": SET_ID,
                "title": "Probe set",
                "timing": {"mode": "cap_bounded", "cap_sec": 300},
                "traversal": "amrap",
                "repeat": 1,
                "work_target": [
                    {
                        "metric": "rounds",
                        "value_form": "open",
                        "value": None,
                        "role": "observation",
                    }
                ],
                "slots": [
                    {
                        "id": SLOT_ID,
                        "exercise_id": EXERCISE_ID,
                        "work_target": [
                            {
                                "metric": "reps",
                                "value_form": "single",
                                "value": 5,
                                "role": "completion",
                            }
                        ],
                        "load": {
                            "value": 40,
                            "unit": "kg",
                            "unit_type": "absolute",
                        },
                        "stimuli": [{"type": "rir", "target": 2}],
                        "post_rest_sec": 0,
                        "is_warmup": False,
                    }
                ],
            }
        ],
    }


def post_json(url: str, payload: object) -> object:
    body = json.dumps(payload).encode()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode())


def run_swift_probe(base_url: str) -> None:
    env = os.environ.copy()
    env.update(
        {
            "WORKOUTDB_SYNC_PROBE_BASE_URL": base_url,
            "WORKOUTDB_SYNC_PROBE_TOKEN": TOKEN,
        }
    )
    result = subprocess.run(
        ["swift", "run", "PrimitiveSyncProbe"],
        cwd=INTEGRATION_DIR,
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Swift sync probe failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_primitive_set_log_upserted(db_path: Path) -> None:
    with sqlite3.connect(db_path) as connection:
        slot_row = connection.execute(
            """
            SELECT id, workout_id, role, reps, weight, weight_unit, planned_exercise_id
            FROM primitive_set_log
            WHERE id = ?
            """,
            (SET_LOG_ID,),
        ).fetchone()
        slot_count = connection.execute(
            "SELECT COUNT(*) FROM primitive_set_log WHERE id = ?",
            (SET_LOG_ID,),
        ).fetchone()[0]
        aggregate_row = connection.execute(
            """
            SELECT id, workout_id, role, slot_id, set_id, block_id, rounds, duration_sec
            FROM primitive_set_log
            WHERE role = 'set_result' AND workout_id = ?
            """,
            (WORKOUT_ID,),
        ).fetchone()
        aggregate_count = connection.execute(
            "SELECT COUNT(*) FROM primitive_set_log WHERE role = 'set_result' AND workout_id = ?",
            (WORKOUT_ID,),
        ).fetchone()[0]

    assert slot_count == 1
    assert slot_row == (
        SET_LOG_ID,
        WORKOUT_ID,
        "slot",
        7,
        40.0,
        "kg",
        EXERCISE_ID,
    )
    assert aggregate_count == 1
    assert aggregate_row == (
        aggregate_row[0],
        WORKOUT_ID,
        "set_result",
        None,
        SET_ID,
        BLOCK_ID,
        3,
        300.0,
    )


@contextmanager
def bound_server_socket() -> Iterator[tuple[socket.socket, int]]:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        sock.listen()
        port = sock.getsockname()[1]
        yield sock, port
