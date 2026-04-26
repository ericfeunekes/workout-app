import os

import pytest


# Replace these with your actual implementations
class InMemoryUserRepo:
    def __init__(self):
        self._data = {}
        self._next = 1

    def save(self, user):
        if any(u["email"] == user["email"] for u in self._data.values()):
            raise ValueError("duplicate email")
        uid = str(self._next)
        self._next += 1
        self._data[uid] = {"id": uid, **user}
        return uid

    def get(self, uid):
        return self._data.get(uid)

    def clear(self):
        self._data.clear()


class PostgresUserRepo:
    # Placeholder; wire to psycopg2/asyncpg in real project
    def __init__(self, dsn):
        self.dsn = dsn

    def save(self, user):
        raise NotImplementedError("Implement against Postgres")

    def get(self, uid):
        raise NotImplementedError

    def clear(self):
        pass


ADAPTERS = [
    pytest.param(lambda: InMemoryUserRepo(), id="mem"),
    pytest.param(
        lambda: PostgresUserRepo(os.environ.get("TEST_DB_DSN", "")),
        id="pg",
        marks=pytest.mark.integration,
    ),
]


@pytest.fixture(params=ADAPTERS)
def repo(request):
    repo = request.param()
    try:
        yield repo
    finally:
        if hasattr(repo, "clear"):
            repo.clear()


def test_saves_and_reads_user(repo):
    uid = repo.save({"email": "a@example.com", "name": "Alice"})
    got = repo.get(uid)
    assert got and got["email"] == "a@example.com"


def test_enforces_unique_email(repo):
    repo.save({"email": "dup@example.com", "name": "A"})
    with pytest.raises(Exception):
        repo.save({"email": "dup@example.com", "name": "B"})
