# Beta Incident Policy — v0.9.0-beta

Scope
-----
This policy governs incident response and hotfix procedures for the v0.9.0-beta release.

Principles
----------
- No changes to readiness semantics or metric names during beta unless explicitly approved by post-incident review.
- Hotfixes limited to critical fixes that cannot wait for the normal release cycle.

Hotfix Process
---------------
1. If a critical issue is detected, create a hotfix branch named `hotfix/<short-desc>` from `main`.
2. Implement minimal changes necessary to fix the bug — no feature work.
3. Add unit tests and update CI as needed.
4. Open a PR titled `hotfix: <short-desc>` and assign SRE and one senior engineer.
5. Merge only after CI green and explicit approval from SRE.
6. Tag the hotfix release with an incrementing pre-release tag (e.g., `v0.9.1-beta-hotfix-1`).

Rollback
--------
- Rollback strategy is to revert the merge commit on `main` and redeploy the previous tag.

Post-Incident Review
---------------------
- Every hotfix requires a post-incident report summarizing root cause, fix, and follow-up actions.

Restrictions
------------
- No metric renames during hotfixes.
- No changes to `/readyz` logic or readiness metric semantics.
