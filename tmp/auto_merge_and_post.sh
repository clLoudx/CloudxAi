#!/usr/bin/env bash
set -euo pipefail
REPO="clLoudx/CloudxAi"
PR_NUM=2
DELAY_SECONDS=3600
LOG=/tmp/auto_merge_and_post.log
echo "Auto-merge watcher started for PR #${PR_NUM}; sleeping ${DELAY_SECONDS}s" >> "$LOG"
sleep "$DELAY_SECONDS"
# Attempt to merge
MERGE_PAYLOAD='{"merge_method":"squash"}'
HTTP_STATUS=$(curl -s -o /tmp/merge_response.json -w "%{http_code}" -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO}/pulls/${PR_NUM}/merge" -d "$MERGE_PAYLOAD")
echo "Merge HTTP status: $HTTP_STATUS" >> "$LOG"
cat /tmp/merge_response.json >> "$LOG" || true
# Check merged
python3 - <<PY >> "$LOG" 2>&1
import json
r=json.load(open('/tmp/merge_response.json'))
if r.get('merged'):
    print('Merged OK')
else:
    print('Merge failed or not merged:', r)
PY
# If merged, update local main and run quick tests
if grep -q '"merged": true' /tmp/merge_response.json 2>/dev/null; then
  echo "Fetching and checking out main" >> "$LOG"
  git fetch origin main >> "$LOG" 2>&1 || true
  if git show-ref --quiet refs/heads/main; then
    git checkout main >> "$LOG" 2>&1 || true
  else
    git checkout -b main origin/main >> "$LOG" 2>&1 || true
  fi
  git pull origin main >> "$LOG" 2>&1 || true
  echo "Running quick step_runner tests" >> "$LOG"
  PYTHONPATH=. pytest -q step_runner/tests/test_runner.py -q >> /tmp/post_merge_test_output.txt 2>&1 || true
  echo "Post-merge tests output saved to /tmp/post_merge_test_output.txt" >> "$LOG"
else
  echo "Not merged; skipping post-merge tasks" >> "$LOG"
fi
