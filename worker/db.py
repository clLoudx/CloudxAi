"""Simple DB helpers for the PHASE-6 worker POC.

Uses SQLite by default for local tests; production will use Postgres and the migration
`migrations/0001_create_jobs.sql`.
"""
from __future__ import annotations

import sqlite3
import json
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any

DEFAULT_DB = "file:phase6_poc.db?mode=memory&cache=shared"


@contextmanager
def get_conn(db_url: Optional[str] = None):
    url = db_url or DEFAULT_DB
    # sqlite in-memory shared cache mode by default; callers can pass a file path
    conn = sqlite3.connect(url, uri=True, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS jobs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          payload TEXT,
          status TEXT NOT NULL DEFAULT 'queued',
          attempts INTEGER NOT NULL DEFAULT 0,
          max_attempts INTEGER NOT NULL DEFAULT 3,
          locked_at REAL,
          locked_by TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        )
        """
    )
    conn.commit()


def enqueue_job(conn: sqlite3.Connection, job_type: str, payload: Optional[Dict[str, Any]] = None, max_attempts: int = 3) -> int:
    now = time.time()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO jobs (type, payload, status, attempts, max_attempts, created_at, updated_at) VALUES (?, ?, 'queued', 0, ?, ?, ?)",
        (job_type, json.dumps(payload or {}), max_attempts, now, now),
    )
    conn.commit()
    return cur.lastrowid


def claim_job(conn: sqlite3.Connection, worker_id: str, lease_seconds: int = 30) -> Optional[Dict[str, Any]]:
    """Atomically claim one eligible job and return it.

    Eligibility: status = 'queued' OR (status='running' AND locked_at < now - lease_seconds)
    """
    now = time.time()
    lease_cutoff = now - lease_seconds
    cur = conn.cursor()
    # Pick one eligible job id
    cur.execute(
        "SELECT id FROM jobs WHERE (status = 'queued') OR (status = 'running' AND locked_at < ?) ORDER BY created_at LIMIT 1",
        (lease_cutoff,)
    )
    row = cur.fetchone()
    if not row:
        return None
    job_id = row[0]
    # Try to atomically update the chosen job to running and set lock
    cur.execute(
        "UPDATE jobs SET status = 'running', locked_at = ?, locked_by = ?, updated_at = ? WHERE id = ?",
        (now, worker_id, now, job_id),
    )
    conn.commit()
    cur.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
    job = cur.fetchone()
    if not job:
        return None
    return dict(job)


def complete_job(conn: sqlite3.Connection, job_id: int) -> None:
    now = time.time()
    cur = conn.cursor()
    cur.execute(
        "UPDATE jobs SET status = 'completed', updated_at = ? WHERE id = ?",
        (now, job_id),
    )
    conn.commit()


def fail_job(conn: sqlite3.Connection, job_id: int) -> None:
    now = time.time()
    cur = conn.cursor()
    # increment attempts, mark failed if >= max_attempts else set back to queued
    cur.execute("SELECT attempts, max_attempts FROM jobs WHERE id = ?", (job_id,))
    row = cur.fetchone()
    if not row:
        return
    attempts, max_attempts = row
    attempts = attempts + 1
    if attempts >= max_attempts:
        cur.execute("UPDATE jobs SET attempts = ?, status = 'failed', updated_at = ? WHERE id = ?", (attempts, now, job_id))
    else:
        cur.execute("UPDATE jobs SET attempts = ?, status = 'queued', locked_at = NULL, locked_by = NULL, updated_at = ? WHERE id = ?", (attempts, now, job_id))
    conn.commit()


def get_job(conn: sqlite3.Connection, job_id: int) -> Optional[Dict[str, Any]]:
    cur = conn.cursor()
    cur.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
    row = cur.fetchone()
    if not row:
        return None
    return dict(row)

