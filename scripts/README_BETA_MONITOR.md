# Beta Monitor — README

This folder contains a helper script to perform passive beta checks and append observations to `BETA_OBSERVATIONS.md`.

How to run (manual):

```bash
python3 scripts/beta_monitor.py
```

Notes:
- The script performs local file inspections only. It does not make network calls or write source code.
- Scheduling should be done externally (cron, operator-run, or orchestration). Do not add CI workflows during beta unless explicitly authorized.
