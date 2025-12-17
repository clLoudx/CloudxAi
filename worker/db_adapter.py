"""Adapter that picks sqlite (POC) or Postgres implementation based on DSN.

Usage: pass a DSN like 'postgres://user:pass@host/db' via environment or function arg.
If DSN is None or a file path, the sqlite POC (`worker.db`) is used.
"""
from __future__ import annotations

import contextlib
import os
from typing import Optional, Dict, Any

from . import db as sqlite_db
db_postgres = None


def _is_postgres_dsn(dsn: Optional[str]) -> bool:
    if not dsn:
        return False
    lower = dsn.lower()
    return lower.startswith("postgres://") or lower.startswith("postgresql://") or "postgres" in lower


@contextlib.contextmanager
def get_conn(dsn: Optional[str] = None):
    if _is_postgres_dsn(dsn):
        # import lazily so tests that don't need psycopg2 won't fail
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        # db_postgres.get_conn returns a connection (not a contextmanager) so wrap it
        conn = db_postgres.get_conn(dsn)
        try:
            yield conn
        finally:
            conn.close()
    else:
        # delegate to sqlite contextmanager
        with sqlite_db.get_conn(dsn) as conn:
            yield conn


def enqueue_job(dsn: Optional[str], *args, **kwargs):
    if _is_postgres_dsn(dsn):
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        with get_conn(dsn) as conn:
            return db_postgres.enqueue_job(conn, *args, **kwargs)
    else:
        with get_conn(dsn) as conn:
            return sqlite_db.enqueue_job(conn, *args, **kwargs)


def claim_job(dsn: Optional[str], *args, **kwargs):
    if _is_postgres_dsn(dsn):
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        with get_conn(dsn) as conn:
            return db_postgres.claim_job(conn, *args, **kwargs)
    else:
        with get_conn(dsn) as conn:
            return sqlite_db.claim_job(conn, *args, **kwargs)


def complete_job(dsn: Optional[str], *args, **kwargs):
    if _is_postgres_dsn(dsn):
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        with get_conn(dsn) as conn:
            return db_postgres.complete_job(conn, *args, **kwargs)
    else:
        with get_conn(dsn) as conn:
            return sqlite_db.complete_job(conn, *args, **kwargs)


def fail_job(dsn: Optional[str], *args, **kwargs):
    if _is_postgres_dsn(dsn):
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        with get_conn(dsn) as conn:
            return db_postgres.fail_job(conn, *args, **kwargs)
    else:
        with get_conn(dsn) as conn:
            return sqlite_db.fail_job(conn, *args, **kwargs)


def get_job(dsn: Optional[str], *args, **kwargs):
    if _is_postgres_dsn(dsn):
        global db_postgres
        if db_postgres is None:
            from . import db_postgres as _db_postgres
            db_postgres = _db_postgres
        with get_conn(dsn) as conn:
            return db_postgres.get_job(conn, *args, **kwargs)
    else:
        with get_conn(dsn) as conn:
            return sqlite_db.get_job(conn, *args, **kwargs)
