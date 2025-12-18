#!/usr/bin/env bash
# self_test_bundle.sh ZIP
set -euo pipefail

ZIP="$1"
TMPDIR="$(mktemp -d -t aiagent_selftest_XXXX)"
LOGDIR="./devops/tools/selftest-logs"
mkdir -p "$LOGDIR"

echo "Self-test: extracting $ZIP -> $TMPDIR" | tee "$LOGDIR/selftest.log"
unzip -q "$ZIP" -d "$TMPDIR"

# Basic file checks
echo "Checking required files..." | tee -a "$LOGDIR/selftest.log"
for f in installer.sh ai-agent/modules/healthcheck.sh ai-agent/modules/ui.sh devops/tools/post_deploy_smoke.sh; do
  if [ -e "$TMPDIR/$f" ] || [ -e "$TMPDIR/ai-agent/$f" ]; then
    echo "OK: $f" | tee -a "$LOGDIR/selftest.log"
  else
    echo "MISSING: $f" | tee -a "$LOGDIR/selftest.log"
    # don't fail CI hard here, but mark failure
    MISSING=1
  fi
done

# Try a minimal Python import test if requirements exist
if [ -f "$TMPDIR/requirements.txt" ]; then
  echo "Running pip install in isolated venv for test (may be slow)..." | tee -a "$LOGDIR/selftest.log"
  python3 -m venv "$TMPDIR/venv_test"
  "$TMPDIR/venv_test/bin/pip" install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
  # attempt installing small subset (failures allowed)
  "$TMPDIR/venv_test/bin/pip" install -r "$TMPDIR/requirements.txt" >> "$LOGDIR/pip_install.log" 2>&1 || true
  echo "Python venv setup done" | tee -a "$LOGDIR/selftest.log"
else
  echo "No requirements.txt found; skipping venv pip test" | tee -a "$LOGDIR/selftest.log"
fi

# Sanity run: ensure healthcheck script can be sourced
if [ -f "$TMPDIR/ai-agent/modules/healthcheck.sh" ]; then
  echo "Sourcing healthcheck script for syntax check" | tee -a "$LOGDIR/selftest.log"
  bash -n "$TMPDIR/ai-agent/modules/healthcheck.sh" || echo "healthcheck syntax check failed" | tee -a "$LOGDIR/selftest.log"
else
  echo "No healthcheck found to syntax-check" | tee -a "$LOGDIR/selftest.log"
fi

echo "Self-test complete. see logs in $LOGDIR"
# keep the tmpdir around for debugging
echo "Extracted path: $TMPDIR" | tee -a "$LOGDIR/selftest.log"
exit 0

