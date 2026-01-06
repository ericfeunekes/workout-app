from __future__ import annotations

from workoutdb.migrations import _iter_sql_statements


def test_iter_sql_statements_handles_comments() -> None:
    sql = """
    -- line comment
    CREATE TABLE test (id INTEGER, note TEXT);
    /* block comment */
    INSERT INTO test (id, note) VALUES (1, 'hello;world');
    """
    statements = _iter_sql_statements(sql)
    assert len(statements) == 2
    assert statements[0].startswith("CREATE TABLE test")
    assert statements[1].startswith("INSERT INTO test")
