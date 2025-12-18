#!/usr/bin/env bash
# verify_and_repair.sh
# Verify key services and optionally run emergency-total-repair.sh
set -euo pipefail

SELF="$(realpath "$0")"
ROOT_DIR="$(dirname "$SELF")"
LOG="/var/log/aiagent-verify-$(date +%Y%m%d_%H%M%S).log"
EMERGENCY_TOOL="${ROOT_DIR}/tools/emergency-total-repair.sh"
AUTO_REPAIR="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --auto-repair) AUTO_REPAIR="yes"; shift;;
    -h|--help) echo "Usage: $0 [--auto-repair]"; exit 0;;
    *) shift;;
  esac
done

log(){ echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }
warn(){ echo "[$(date -Iseconds)] WARN: $*" | tee -a "$LOG" >&2; }
err(){ echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG" >&2; exit 1; }

log "Starting verification"

# 1) dpkg health
if dpkg -l >/dev/null 2>&1; then
  log "dpkg query OK"
else
  warn "dpkg query failed"
  [ "$AUTO_REPAIR" = "yes" ] && { [ -x "$EMERGENCY_TOOL" ] && sudo bash "$EMERGENCY_TOOL" --full-auto --repair-systemd --non-interactive || warn "no emergency tool" ; }
fi

# 2) check python imports
VENV="${ROOT_DIR}/venv"
if [ -x "${VENV}/bin/python" ]; then
  log "Testing python imports in venv"
  "${VENV}/bin/python" - <<'PY' >> "$LOG" 2>&1 || true
import importlib, sys
reqs = ['flask','redis','rq','requests']
miss = [r for r in reqs if importlib.util.find_spec(r) is None]
print("MISSING:"+",".join(miss) if miss else "OK")
PY
  grep -q "MISSING" "$LOG" && {
    warn "Python venv: some packages missing"
    [ "$AUTO_REPAIR" = "yes" ] && {
      log "Attempting venv pip install"
      "${VENV}/bin/pip" install -r "${ROOT_DIR}/requirements.txt" >> "$LOG" 2>&1 || warn "pip install in venv failed"
    }
  } || log "Python imports OK"
else
  warn "Venv python not found at $VENV"
  [ "$AUTO_REPAIR" = "yes" ] && { [ -x "$EMERGENCY_TOOL" ] && sudo bash "$EMERGENCY_TOOL" --full-auto --venv-path "$VENV" || true; }
fi

# 3) systemd units status
services=(aiagent-app aiagent-rq)
for s in "${services[@]}"; do
  if systemctl list-unit-files | grep -q "^${s}.service"; then
    if systemctl is-active --quiet "${s}.service"; then
      log "${s}.service active"
    else
      warn "${s}.service inactive"
      [ "$AUTO_REPAIR" = "yes" ] && { sudo systemctl restart "${s}.service" >> "$LOG" 2>&1 || warn "failed restart ${s}"; }
    fi
  else
    warn "${s}.service missing"
    [ "$AUTO_REPAIR" = "yes" ] && { [ -x "$EMERGENCY_TOOL" ] && sudo bash "$EMERGENCY_TOOL" --full-auto --repair-systemd --non-interactive || warn "emergency tool missing"; }
  fi
done

# 4) web endpoint check
if curl -sS --fail http://127.0.0.1:8000/healthz >/dev/null 2>&1; then
  log "HTTP /healthz OK"
else
  warn "/healthz failed"
  [ "$AUTO_REPAIR" = "yes" ] && { [ -x "$EMERGENCY_TOOL" ] && sudo bash "$EMERGENCY_TOOL" --full-auto --non-interactive || warn "no emergency tool" ; }
fi

log "Verification finished. Log: $LOG"

