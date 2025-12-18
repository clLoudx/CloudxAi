import os
import pathlib
import pytest


DSN = os.environ.get("DATABASE_DSN")

try:
    import psycopg2  # type: ignore
    from worker import db_postgres
    PSYCOPG2_AVAILABLE = True
except Exception:
    PSYCOPG2_AVAILABLE = False


pytestmark = pytest.mark.skipif(not (DSN and PSYCOPG2_AVAILABLE), reason="Postgres DSN not set or psycopg2 unavailable")


def _apply_migrations(conn):
    # Apply SQL files under migrations/ in lexicographic order
    base = pathlib.Path(__file__).resolve().parent.parent
    mig_dir = base / "migrations"
    files = sorted(mig_dir.glob("*.sql"))
    cur = conn.cursor()
    for p in files:
        sql = p.read_text(encoding="utf-8")
        cur.execute(sql)
    conn.commit()


def test_postgres_enqueue_claim_complete():
    # This test runs only when DATABASE_DSN is provided and psycopg2 is installed.
    conn = db_postgres.get_conn(DSN)
    try:
        # Ensure schema is present
        _apply_migrations(conn)

        # Enqueue a job
        job_id = db_postgres.enqueue_job(conn, "integration-test", {"hello": "world"}, max_attempts=2)
        assert isinstance(job_id, int)

        # Claim the job
        claimed = db_postgres.claim_job(conn, worker_id="pg-test-worker", lease_seconds=30)
        assert claimed is not None
        assert claimed["id"] == job_id

        # Complete the job
        db_postgres.complete_job(conn, job_id)

        # Verify status
        job = db_postgres.get_job(conn, job_id)
        assert job is not None
        assert job["status"] == "completed"
    finally:
        # Best-effort cleanup: remove the jobs table so repeated runs start clean
        cur = conn.cursor()
        try:
            cur.execute("DROP TABLE IF EXISTS jobs")
            conn.commit()
        except Exception:
            conn.rollback()
        conn.close()
