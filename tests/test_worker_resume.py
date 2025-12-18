import time
import threading
from worker.db import get_conn, init_db, enqueue_job, claim_job, complete_job, get_job
from worker.worker import Worker


def test_claim_after_lease_expiry():
    # Use shared in-memory sqlite DB
    db_url = "phase6_test.db"
    with get_conn(db_url) as conn:
        init_db(conn)
        job_id = enqueue_job(conn, 'sleep', {'seconds': 1}, max_attempts=2)
        # Simulate job claimed by worker A and locked in the past (expired)
        now = time.time()
        past = now - 10
        cur = conn.cursor()
        cur.execute("UPDATE jobs SET status='running', locked_at = ?, locked_by = ? WHERE id = ?", (past, 'worker-A', job_id))
        conn.commit()

    # Now start a worker B which should be able to claim because lease_seconds default is 2
    worker = Worker('worker-B', db_url=db_url, lease_seconds=2)
    t = threading.Thread(target=worker.start, kwargs={'loop_delay': 0.05}, daemon=True)
    t.start()

    # Give the worker some time to pick up and complete the job
    time.sleep(1.5)
    worker.stop()
    t.join(timeout=1.0)

    with get_conn(db_url) as conn:
        job = get_job(conn, job_id)
        assert job is not None
        assert job['status'] == 'completed'


def test_resume_after_crash():
    db_url = "phase6_test2.db"
    with get_conn(db_url) as conn:
        init_db(conn)
        job_id = enqueue_job(conn, 'sleep', {'seconds': 1}, max_attempts=3)
    # Start worker C but stop it immediately after it claims the job to simulate crash
    with get_conn(db_url) as conn:
        # ensure job is queued
        pass

    # Start worker and let it claim the job but not finish
    from worker.db import claim_job as claim
    with get_conn(db_url) as conn:
        job = claim(conn, 'worker-C', lease_seconds=5)
        assert job is not None
        # simulate crash by not completing
    # Now wait for lease to expire and start another worker D to recover
    time.sleep(6)
    worker_d = Worker('worker-D', db_url=db_url, lease_seconds=2)
    t = threading.Thread(target=worker_d.start, kwargs={'loop_delay': 0.05}, daemon=True)
    t.start()
    time.sleep(2.0)
    worker_d.stop()
    t.join(timeout=1.0)
    with get_conn(db_url) as conn:
        job = get_job(conn, job_id)
        assert job is not None
        assert job['status'] == 'completed'
