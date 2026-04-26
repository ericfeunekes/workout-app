"""
Data pipeline tests (DuckDB) with MERGE for portability.
"""

import duckdb
import pytest


def transform_sales_data(source_data: list[dict]) -> list[dict]:
    return [
        {"id": row["id"], "customer_name": row["name"], "amount_cents": row["amount"] * 100}
        for row in source_data
    ]


def run_pipeline(source_data: list[dict], conn):
    transformed = transform_sales_data(source_data)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS sales (
            id INTEGER PRIMARY KEY,
            customer_name VARCHAR,
            amount_cents INTEGER
        )
    """)
    for row in transformed:
        conn.execute(
            """
            MERGE INTO sales t
            USING (SELECT ? AS id, ? AS customer_name, ? AS amount_cents) s
            ON t.id = s.id
            WHEN MATCHED THEN UPDATE SET
              customer_name = s.customer_name,
              amount_cents = s.amount_cents
            WHEN NOT MATCHED THEN INSERT (id, customer_name, amount_cents)
            VALUES (s.id, s.customer_name, s.amount_cents)
            """,
            [row["id"], row["customer_name"], row["amount_cents"]],
        )


def check_data_quality(conn) -> dict:
    negative_count = conn.execute("SELECT COUNT(*) FROM sales WHERE amount_cents < 0").fetchone()[0]
    null_names = conn.execute("SELECT COUNT(*) FROM sales WHERE customer_name IS NULL").fetchone()[
        0
    ]
    return {
        "passed": negative_count == 0 and null_names == 0,
        "negative_amounts": negative_count,
        "null_names": null_names,
    }


@pytest.fixture
def duckdb_conn():
    conn = duckdb.connect(":memory:")
    yield conn
    conn.close()


@pytest.mark.component
@pytest.mark.pipelines
def test_transform_sales_data():
    src = [{"id": 1, "name": "Alice", "amount": 100}, {"id": 2, "name": "Bob", "amount": 200}]
    out = transform_sales_data(src)
    assert out[0]["customer_name"] == "Alice" and out[0]["amount_cents"] == 10000
    assert out[1]["customer_name"] == "Bob" and out[1]["amount_cents"] == 20000


@pytest.mark.component
@pytest.mark.pipelines
def test_extract_transform_load(duckdb_conn):
    src = [{"id": 1, "name": "Alice", "amount": 100}, {"id": 2, "name": "Bob", "amount": 200}]
    run_pipeline(src, duckdb_conn)
    result = duckdb_conn.execute("SELECT * FROM sales ORDER BY id").fetchall()
    assert result == [(1, "Alice", 10000), (2, "Bob", 20000)]


@pytest.mark.dq
@pytest.mark.component
@pytest.mark.pipelines
def test_data_quality_checks_pass_for_valid_data(duckdb_conn):
    duckdb_conn.execute(
        "CREATE TABLE sales AS SELECT 1 id, 'Alice' customer_name, 10000 amount_cents"
    )
    dq = check_data_quality(duckdb_conn)
    assert dq["passed"] and dq["negative_amounts"] == 0 and dq["null_names"] == 0


@pytest.mark.dq
@pytest.mark.component
@pytest.mark.pipelines
def test_data_quality_detects_negative_amounts(duckdb_conn):
    duckdb_conn.execute("CREATE TABLE sales AS SELECT 1 id, 'Bob' customer_name, -5 amount_cents")
    dq = check_data_quality(duckdb_conn)
    assert dq["passed"] is False and dq["negative_amounts"] == 1


@pytest.mark.component
@pytest.mark.pipelines
def test_pipeline_is_idempotent(duckdb_conn):
    src = [{"id": 1, "name": "Alice", "amount": 100}]
    run_pipeline(src, duckdb_conn)
    c1 = duckdb_conn.execute("SELECT COUNT(*) FROM sales").fetchone()[0]
    run_pipeline(src, duckdb_conn)
    c2 = duckdb_conn.execute("SELECT COUNT(*) FROM sales").fetchone()[0]
    assert c1 == c2 == 1


@pytest.mark.component
@pytest.mark.pipelines
def test_pipeline_updates_existing_records(duckdb_conn):
    run_pipeline([{"id": 1, "name": "Alice", "amount": 100}], duckdb_conn)
    run_pipeline([{"id": 1, "name": "Alice", "amount": 150}], duckdb_conn)
    amount = duckdb_conn.execute("SELECT amount_cents FROM sales WHERE id=1").fetchone()[0]
    assert amount == 15000


@pytest.mark.component
@pytest.mark.pipelines
@pytest.mark.p0
def test_critical_pipeline_workflow(duckdb_conn):
    src = [{"id": 1, "name": "Alice", "amount": 100}, {"id": 2, "name": "Bob", "amount": 200}]
    run_pipeline(src, duckdb_conn)
    count = duckdb_conn.execute("SELECT COUNT(*) FROM sales").fetchone()[0]
    assert count == 2
    assert check_data_quality(duckdb_conn)["passed"] is True
