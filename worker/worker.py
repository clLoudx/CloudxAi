"""Minimal worker loop for PHASE-6 POC.

This worker polls the DB, claims jobs (with lease), runs them via runner.run_job,
and marks them completed or failed. The implementation is intentionally small and
synchronous to make tests deterministic.
"""
from __future__ import annotations

import time
import threading
from typing import Optional
from datetime import datetime
from prometheus_client import Counter, Gauge

import os

from .db import init_db
from .db_adapter import get_conn, claim_job, complete_job, fail_job, enqueue_job
from .runner import run_job

# Simple metrics registered on import (tests here run in process)
TASK_SUBMITTED = Counter('phase6_task_submitted_total', 'Total tasks submitted')
TASK_RUNNING = Gauge('phase6_task_running', 'Number of tasks currently running')
TASK_COMPLETED = Counter('phase6_task_completed_total', 'Total tasks completed')
TASK_FAILED = Counter('phase6_task_failed_total', 'Total tasks failed')
TASK_RECOVERED = Counter('phase6_task_recovered_total', 'Total tasks recovered after lease expiry')


class Worker:
    def __init__(self, worker_id: str, db_url: Optional[str] = None, lease_seconds: int = 2):
        self.worker_id = worker_id
        self.db_url = db_url
        self.lease_seconds = lease_seconds
        self._stop = threading.Event()

    def start(self, loop_delay: float = 0.1):
        # If using sqlite (default), ensure schema exists. For Postgres, migrations should be applied externally.
        if not (self.db_url and (self.db_url.startswith('postgres://') or self.db_url.startswith('postgresql://') or 'postgres' in (self.db_url or '').lower())):
            with get_conn(self.db_url) as conn:
                init_db(conn)

        while not self._stop.is_set():
            # claim_job is implemented in db_adapter and will open/close connections as needed
            job = claim_job(self.db_url, self.worker_id, lease_seconds=self.lease_seconds)
            if not job:
                time.sleep(loop_delay)
                continue
            TASK_RUNNING.inc()
            try:
                # run job
                run_job(job)
                complete_job(self.db_url, job['id'])
                TASK_COMPLETED.inc()
            except Exception:
                fail_job(self.db_url, job['id'])
                TASK_FAILED.inc()
            finally:
                TASK_RUNNING.dec()

    def stop(self):
        self._stop.set()

