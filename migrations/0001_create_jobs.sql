-- initial job table for PHASE-6.1 POC

-- This is a Postgres-flavored schema intended as a starting point for the job table.
-- It is intentionally simple and designed to capture the essential fields for a restart-safe worker.

CREATE TABLE IF NOT EXISTS jobs (
  id BIGSERIAL PRIMARY KEY,
  type TEXT NOT NULL,
  payload JSONB,
  status TEXT NOT NULL DEFAULT 'queued',
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 3,
  locked_at TIMESTAMPTZ,
  locked_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_jobs_status_created_at ON jobs(status, created_at);

-- Example row locking pattern: use UPDATE ... WHERE id = <id> AND (locked_at IS NULL OR locked_at < now() - 'lease seconds'::interval)

