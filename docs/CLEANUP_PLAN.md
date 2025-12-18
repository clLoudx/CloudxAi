# Non-Destructive Git-Index Cleanup Plan

Purpose: remove generated artifacts and large files from the git index without deleting local files. This plan is non-destructive: it only removes files from tracking and updates `.gitignore` so the files are not re-added.

DO NOT RUN ANY COMMANDS UNLESS YOU UNDERSTAND THEM. Review carefully and run in a disposable branch.

## Why
- Removes noise from diffs and PRs
- Prevents accidental commits of environment artifacts and DBs
- Improves CI reliability and reduces storage/bandwidth

## Files targeted (examples)
- `__pycache__/` and `*.pyc`
- `.venv/`, `venv/`
- `*.db`, `*.sqlite`, `*.sqlite3`
- Local environment markers like `.reverse-env/` and `.phase-env/`

## Steps (preview, then apply)

1) Create a disposable branch for cleanup

```bash
git checkout -b chore/hygiene/cleanup-index
```

2) Preview files currently tracked that match cleanup patterns

```bash
# List tracked files matching patterns
git ls-files --cached | grep -E "(__pycache__|\.pyc$|\.db$|\.sqlite$|\.sqlite3$|\.venv/|venv/|\.reverse-env/|\.phase-env/)" || true
```

3) Add `.gitignore` (if not already added)

```bash
# Edit .gitignore as needed, then:
git add .gitignore
```

4) Remove from git index only (does not delete local files)

```bash
# This removes the matching files from the index only. Adjust patterns as needed.
# IMPORTANT: do not run this against production DBs. Verify the preview output first.
# Remove directories recursively and files by pattern:
git rm --cached -r __pycache__ || true
git rm --cached -r .venv || true
git rm --cached -r venv || true
# Remove tracked DB files
git ls-files --cached | grep -E "(\.db$|\.sqlite$|\.sqlite3$)" | xargs -r git rm --cached || true
# Remove pyc
git ls-files --cached | grep -E "\.pyc$" | xargs -r git rm --cached || true
```

5) Commit the index updates

```bash
git commit -m "chore: remove generated artifacts from git index; update .gitignore"
```

6) Push branch and open PR

```bash
git push --set-upstream origin chore/hygiene/cleanup-index
# Open PR via GitHub UI; include the cleanup plan in description
```

## Rollback (if something unexpected happens)

- If you haven't pushed the branch yet and want to revert the index changes locally:

```bash
# Reset staged/index changes to HEAD
git reset --hard HEAD
# Restore files to tracked state if needed
# If files were removed from the working tree (shouldn't happen with --cached), restore from origin
```

- If you pushed and want to undo the commit on the remote branch (before merge):

```bash
# Force push a branch reset to previous commit (use with caution)
git reset --hard origin/phase-6/harden-postgres
git push --force-with-lease origin chore/hygiene/cleanup-index
```

## Safety warnings
- DO NOT run the cleanup commands against production systems or directories containing production database files.
- Always preview the `git ls-files --cached` output before removing from index.
- Prefer human review on the PR before merging.

## Reviewer checklist (include in PR description)
- [ ] `.gitignore` additions are correct and intentional
- [ ] No runtime code was changed
- [ ] Only git-index (tracking) was modified
- [ ] Local files remain present on disk
- [ ] Rollback instructions are present and tested
- [ ] CI is pointed at clean artifacts

---

If you'd like, I can prepare the branch and the PR description as a draft (I will not run git commands unless you instruct me to).