#!/usr/bin/env bash
set -euo pipefail
LOG=/workspaces/AiCloudxAgent/tmp/poll_merge.log
REPO=clLoudx/CloudxAi
PR=2
MAX=20
SLEEP=15
echo "Start polling PR $PR" > "$LOG"
state=unknown
for i in $(seq 1 $MAX); do
  curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/pulls/$PR" -o /workspaces/AiCloudxAgent/tmp/pr_poll.json || true
  python3 - <<'PY' > /workspaces/AiCloudxAgent/tmp/pr_poll_state.txt
import json
try:
    r=json.load(open('/workspaces/AiCloudxAgent/tmp/pr_poll.json'))
    if r.get('draft'):
        print('draft')
    else:
        print('ready')
except Exception:
    print('error')
PY
  state=$(cat /workspaces/AiCloudxAgent/tmp/pr_poll_state.txt 2>/dev/null || echo error)
  echo "$(date -u) attempt $i state=$state" >> "$LOG"
  if [ "$state" = "ready" ]; then
    echo "PR is ready" >> "$LOG"
    break
  fi
  sleep $SLEEP
done

if [ "$state" != "ready" ]; then
  echo "PR did not become ready after $MAX attempts" >> "$LOG"
  exit 2
fi

# attempt merge
echo "Attempting merge" >> "$LOG"
MERGE_PAYLOAD='{"merge_method":"squash"}'
curl -s -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/pulls/$PR/merge" -d "$MERGE_PAYLOAD" -o /workspaces/AiCloudxAgent/tmp/merge_response.json -w "%{http_code}\n" >> "$LOG" 2>&1 || true
python3 - <<'PY' >> "$LOG" 2>&1
import json
try:
    r=json.load(open('/workspaces/AiCloudxAgent/tmp/merge_response.json'))
    print('merge_response=', r)
except Exception as e:
    print('no merge_response file or invalid json', e)
PY

if grep -q '"merged": true' /workspaces/AiCloudxAgent/tmp/merge_response.json 2>/dev/null; then
  echo "Merged successfully" >> "$LOG"
  git fetch origin main >> "$LOG" 2>&1 || true
  if git show-ref --quiet refs/heads/main; then git checkout main >> "$LOG" 2>&1 || true; else git checkout -b main origin/main >> "$LOG" 2>&1 || true; fi
  git pull origin main >> "$LOG" 2>&1 || true
  echo "Running quick tests" >> "$LOG"
  PYTHONPATH=. pytest -q step_runner/tests/test_runner.py -q > /workspaces/AiCloudxAgent/tmp/post_merge_test_output.txt 2>&1 || true
  echo "Post-merge tests saved" >> "$LOG"
else
  echo "Merge failed or not permitted" >> "$LOG"
fi

echo "Done" >> "$LOG"
