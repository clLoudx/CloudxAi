"""Simple migration runner for PHASE-6 job table migrations.

Usage (development):
  # apply against a Postgres DSN
  DATABASE_DSN=postgres://user:pass@host/db python tools/apply_migrations.py

This script is intentionally minimal: it reads files in `migrations/` and applies
them in lexicographic order. It will attempt to connect with psycopg2 if available
and will print instructions otherwise.
"""
from __future__ import annotations

import os
import glob
import sys

DSN = os.environ.get("DATABASE_DSN")


def main():
    if not DSN:
        print("No DATABASE_DSN set. To apply migrations against Postgres set DATABASE_DSN and retry.")
        print("E.g. DATABASE_DSN=postgres://user:pass@host/db python tools/apply_migrations.py")
        sys.exit(1)

    try:
        import psycopg2
    except Exception as e:
        print("psycopg2 is not installed in this environment. Install it to run migrations against Postgres.")
        print("Alternatively, review the SQL files under migrations/ and apply them via your DB tooling.")
        sys.exit(1)

    migration_files = sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "migrations", "*.sql")))
    if not migration_files:
        print("No migration files found under migrations/")
        return

    conn = psycopg2.connect(DSN)
    try:
        cur = conn.cursor()
            # Ensure schema_migrations table exists
            cur.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                filename TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ DEFAULT now()
            )
            """)
            conn.commit()
            for path in migration_files:
                fname = os.path.basename(path)
                # Check if migration already applied
                cur.execute("SELECT 1 FROM schema_migrations WHERE filename = %s", (fname,))
                if cur.fetchone():
                    print(f"Skipping already applied migration: {fname}")
                    continue
                print(f"Applying {path}...")
                with open(path, "r", encoding="utf-8") as fh:
                    sql = fh.read()
                cur.execute(sql)
                cur.execute("INSERT INTO schema_migrations (filename) VALUES (%s)", (fname,))
                conn.commit()
            print("Migrations applied.")
    finally:
        conn.close()


if __name__ == '__main__':
    main()
