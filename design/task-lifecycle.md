# Task lifecycle (PHASE-6.1)

This document describes the minimal task lifecycle for the PHASE-6 execution engine POC.

States

- queued: task is created and awaiting worker claim
- running: worker claimed the task and is executing it
- completed: task succeeded
- failed: task reached max attempts or terminal failure
- cancelled: admin cancelled the task

Transitions

- queued -> running: worker atomically claims a queued task and sets `locked_at` and `locked_by`
- running -> completed: worker marks task completed and clears locks
- running -> failed: worker marks failed and increments attempts
- running -> queued: lease expired and a different worker reclaims the task (increment attempts on re-run)

Lease model

Workers claim tasks by performing an atomic UPDATE that sets `locked_at` and `locked_by` and transitions `status` to `running` for eligible rows: queued tasks or running tasks with expired lease.

A short lease (e.g., 30s) prevents long-running stuck tasks from blocking progress; the worker must renew or complete before lease expiry.

Idempotency

Task handler functions must be idempotent. The POC will run only stateless echo/noop tasks; full idempotency strategy will be designed in later phases.

