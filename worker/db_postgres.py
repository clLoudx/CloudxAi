"""Postgres adapter for job table operations.

This module provides a minimal set of functions mirroring the sqlite POC but
implemented with psycopg2 for Postgres. It is intended for PHASE-6.1 hardening.
"""
from __future__ import annotations

import json
import time
from typing import Optional, Dict, Any

import psycopg2
import psycopg2.extras


def get_conn(dsn: str):
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    return conn


def enqueue_job(conn, job_type: str, payload: Optional[Dict[str, Any]] = None, max_attempts: int = 3) -> int:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO jobs (type, payload, status, attempts, max_attempts, created_at, updated_at) VALUES (%s, %s, 'queued', 0, %s, now(), now()) RETURNING id",
        (job_type, json.dumps(payload or {}), max_attempts),
    )
    job_id = cur.fetchone()[0]
    conn.commit()
    return job_id


def claim_job(conn, worker_id: str, lease_seconds: int = 30) -> Optional[Dict[str, Any]]:
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    # Try to atomically claim one eligible job using UPDATE ... RETURNING
    cur.execute(
        """
        UPDATE jobs
        SET status='running', locked_at = now(), locked_by = %s, updated_at = now()
        WHERE id = (
            SELECT id FROM jobs
            WHERE (status = 'queued') OR (status = 'running' AND locked_at < now() - make_interval(secs => %s))
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED
            LIMIT 1
        )
        RETURNING *
        """,
        (worker_id, lease_seconds),
    )
    row = cur.fetchone()
    if not row:
        conn.rollback()
        return None
    conn.commit()
    return dict(row)


def claim_job_with_advisory(conn, worker_id: str, lease_seconds: int = 30) -> Optional[Dict[str, Any]]:
    """Claim a job using pg_try_advisory_lock to avoid high contention on UPDATE.

    This will attempt to atomically pick a candidate job and acquire a session
    advisory lock on the job id. If the advisory lock cannot be acquired the
    UPDATE will not return rows and the function returns None.
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    # Use pg_try_advisory_lock(id) in the WHERE clause so the row is only
    # updated when the lock is successfully acquired in this session.
    cur.execute(
        """
        UPDATE jobs
        SET status='running', locked_at = now(), locked_by = %s, updated_at = now()
        WHERE id = (
            SELECT id FROM jobs
            WHERE (status = 'queued') OR (status = 'running' AND locked_at < now() - make_interval(secs => %s))
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED
            LIMIT 1
        )
        AND pg_try_advisory_lock(id)
        RETURNING *
        """,
        (worker_id, lease_seconds),
    )
    row = cur.fetchone()
    if not row:
        conn.rollback()
        return None
    conn.commit()
    return dict(row)


def complete_job(conn, job_id: int) -> None:
    cur = conn.cursor()
    cur.execute("UPDATE jobs SET status='completed', updated_at = now() WHERE id = %s", (job_id,))
    conn.commit()


def fail_job(conn, job_id: int) -> None:
    cur = conn.cursor()
    cur.execute("SELECT attempts, max_attempts FROM jobs WHERE id = %s", (job_id,))
    row = cur.fetchone()
    if not row:
        conn.rollback()
        return
    attempts, max_attempts = row
    attempts = attempts + 1
    if attempts >= max_attempts:
        cur.execute("UPDATE jobs SET attempts = %s, status = 'failed', updated_at = now() WHERE id = %s", (attempts, job_id))
    else:
        cur.execute("UPDATE jobs SET attempts = %s, status = 'queued', locked_at = NULL, locked_by = NULL, updated_at = now() WHERE id = %s", (attempts, job_id))
    conn.commit()


def get_job(conn, job_id: int) -> Optional[Dict[str, Any]]:
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM jobs WHERE id = %s", (job_id,))
    row = cur.fetchone()
    if not row:
        return None
    return dict(row)
