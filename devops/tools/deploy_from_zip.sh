#!/usr/bin/env bash
# deploy_from_zip.sh /path/to/aiagent_release.zip [--target /opt/ai-agent] [--attempts 3] [--non-interactive]
set -euo pipefail
ZIP="$1"; shift || true
TARGET="${TARGET:-/opt/ai-agent}"; ATTEMPTS=3; NON_INTERACTIVE="no"
while [ $# -gt 0 ]; do case "$1" in --target) TARGET="$2"; shift 2;; --attempts) ATTEMPTS="$2"; shift 2;; --non-interactive) NON_INTERACTIVE="yes"; shift;; *) shift;; esac; done
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
[ -f "$ZIP" ] || { echo "Zip not found: $ZIP"; exit 2; }
LOGDIR="/var/log/aiagent_deploy_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$LOGDIR"
TMPDIR="$(mktemp -d -t aiagent_deploy_XXXX)"; trap 'rm -rf "$TMPDIR"' EXIT
unzip -q "$ZIP" -d "$TMPDIR"
INST=""
[ -f "$TMPDIR/installer.sh" ] && INST="$TMPDIR/installer.sh" || { [ -f "$TMPDIR/ai-agent/installer.sh" ] && INST="$TMPDIR/ai-agent/installer.sh"; }
[ -n "$INST" ] || { echo "installer.sh missing in archive"; exit 3; }
chmod +x "$INST"
mkdir -p "$TARGET"
rsync -a --delete "$TMPDIR/" "$TARGET/" | tee -a "$LOGDIR/deploy.log"
run_with_retries(){
  local cmd="$*"; local attempt=1
  while [ $attempt -le "$ATTEMPTS" ]; do
    echo "Installer attempt #$attempt" | tee -a "$LOGDIR/deploy.log"
    if "$cmd"; then echo "Installer success" | tee -a "$LOGDIR/deploy.log"; return 0; fi
    echo "Installer failed attempt #$attempt" | tee -a "$LOGDIR/deploy.log"
    if [ -x "$TARGET/tools/emergency-total-repair.sh" ]; then
      echo "Attempting emergency repair..." | tee -a "$LOGDIR/deploy.log"
      sudo "$TARGET/tools/emergency-total-repair.sh" --full-auto --self-heal --restart-agent --non-interactive >> "$LOGDIR/emergency_repair.log" 2>&1 || true
    fi
    attempt=$((attempt+1)); sleep $((5 * attempt))
  done
  return 1
}
if [ "$NON_INTERACTIVE" = "yes" ]; then run_with_retries sudo "$INST" --non-interactive >> "$LOGDIR/installer.log" 2>&1 || { echo "Installer failed"; exit 4; }
else run_with_retries sudo "$INST" >> "$LOGDIR/installer.log" 2>&1 || { echo "Installer failed"; exit 4; }; fi
# Run smoke test:
if command -v curl >/dev/null 2>&1; then
  echo "Running post-deploy smoke..." | tee -a "$LOGDIR/deploy.log"
  if [ -f "$TARGET/devops/tools/post_deploy_smoke.sh" ]; then "$TARGET/devops/tools/post_deploy_smoke.sh" aiagent aiagent-web /healthz 8000 60 >> "$LOGDIR/smoke.log" 2>&1 || true; else curl -fsS --max-time 5 http://127.0.0.1:8000/healthz >/dev/null 2>&1 && echo "Healthz OK" || echo "Healthz failed"; fi
fi
echo "Deployment finished. Logs: $LOGDIR"
exit 0

