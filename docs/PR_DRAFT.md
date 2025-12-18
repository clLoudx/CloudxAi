Title: chore: repository hygiene (.gitignore + safe cleanup plan)

Summary
Adds enterprise-safe .gitignore rules and a non-destructive cleanup plan to
remove generated artifacts from Git tracking without deleting local files.

What's included
- .gitignore covering pycache, virtualenvs, sqlite dbs, env files
- CLEANUP_PLAN.md with preview commands, safe git rm --cached steps, and rollback

Safety
- No runtime or logic changes
- No files deleted from disk
- Fully reversible

Reviewer checklist
- [ ] No behavior changes
- [ ] Index-only cleanup
- [ ] Rollback documented

How to open the PR
- Visit: https://github.com/clLoudx/CloudxAi/pull/new/chore/phase-6/hygiene
- Or run: gh pr create --base phase-6/harden-postgres --head chore/phase-6/hygiene --title "chore: repository hygiene (.gitignore + safe cleanup plan)" --body-file docs/CLEANUP_PLAN.md --draft
