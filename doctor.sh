#!/usr/bin/env bash
# doctor.sh - System diagnostics & repair assistant for AI Agent
# Usage: sudo ./doctor.sh [--auto-fix] [--yes] [--full] [--help]
set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/var/log/aiagent_doctor_$(date +%Y%m%d_%H%M%S).log"
EMERGENCY_TOOL="${REPO_ROOT}/tools/emergency-total-repair.sh"
AUTO_FIX="no"
NON_INTERACTIVE="no"
FULL="no"

info(){ printf "[INFO] %s\n" "$*" | tee -a "$LOGFILE"; }
warn(){ printf "[WARN] %s\n" "$*" | tee -a "$LOGFILE" >&2; }
err(){ printf "[ERR] %s\n" "$*" | tee -a "$LOGFILE" >&2; }
run(){ eval "$@" >> "$LOGFILE" 2>&1; }

usage(){
  cat <<EOF
doctor.sh - Run diagnostics and optional repairs

Usage:
  sudo ./doctor.sh [options]

Options:
  --auto-fix        : attempt safe automatic fixes where possible
  --yes             : assume yes for prompts (non-interactive)
  --full            : run extended checks (may be slower)
  -h, --help        : show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --auto-fix) AUTO_FIX="yes"; shift;;
    --yes|--non-interactive) NON_INTERACTIVE="yes"; shift;;
    --full) FULL="yes"; shift;;
    -h|--help) usage;;
    *) shift;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then err "Please run as root (sudo)"; fi

touch "$LOGFILE"
info "Doctor started - log: $LOGFILE"

# Check apt/dpkg health
info "Checking dpkg/apt status"
set +e
dpkg --audit >> "$LOGFILE" 2>&1
dpkg_audit_rc=$?
set -e
if [ $dpkg_audit_rc -ne 0 ]; then
  warn "dpkg audit reported issues"
  if [ "$AUTO_FIX" = "yes" ] || [ "$NON_INTERACTIVE" = "yes" ]; then
    info "Running dpkg --configure -a and apt-get install -f (auto-fix enabled)"
    run "dpkg --configure -a || true"
    run "apt-get install -f -y || true"
  else
    warn "Run the repair manually: sudo dpkg --configure -a && sudo apt-get install -f -y"
  fi
else
  info "dpkg database seems OK"
fi

# Check systemd services
info "Checking systemd service statuses"
SERVICES=(aiagent-app aiagent-rq aiagent)
for s in "${SERVICES[@]}"; do
  if systemctl list-units --full -all | grep -q "^${s}\.service"; then
    info "Status for ${s}.service:"
    systemctl status "${s}.service" --no-pager | sed -n '1,6p' | tee -a "$LOGFILE"
    if ! systemctl is-active --quiet "${s}.service"; then
      warn "${s}.service is not active"
      if [ "$AUTO_FIX" = "yes" ]; then
        info "Attempting restart of ${s}.service"
        run "systemctl restart ${s}.service || true"
      fi
    else
      info "${s}.service active"
    fi
  else
    warn "${s}.service not present"
  fi
done

# Check Python virtualenv and imports
info "Checking Python venv and imports (if present)"
# try to determine venv path: /opt/ai-agent/venv (canonical), /opt/aiagent/venv (legacy), or repo venv
CANDIDATES=("/opt/ai-agent/venv" "/opt/aiagent/venv" "${REPO_ROOT}/venv" "${REPO_ROOT}/ai-agent/venv")
VENV_FOUND=""
for v in "${CANDIDATES[@]}"; do
  if [ -x "${v}/bin/python" ]; then VENV_FOUND="$v"; break; fi
done
if [ -n "$VENV_FOUND" ]; then
  info "Using venv at $VENV_FOUND"
  PY="$VENV_FOUND/bin/python"
  TMP="/tmp/aiagent_import_check.$$"
  "$PY" - <<'PY' > "$TMP" 2>&1 || true
import importlib,sys
reqs = ['flask','redis','rq','requests']
missing=[r for r in reqs if importlib.util.find_spec(r) is None]
print("MISSING:"+",".join(missing) if missing else "OK")
PY
  if grep -q "^OK" "$TMP"; then
    info "Core Python packages import OK"
  else
    warn "Python import issues: $(cat $TMP)"
    if [ "$AUTO_FIX" = "yes" ]; then
      info "Installing requirements (if requirements.txt exists)"
      REQ="${REPO_ROOT}/requirements.txt"
      if [ -f "$REQ" ]; then
        run "\"$VENV_FOUND/bin/pip\" install -r \"$REQ\" || true"
      else
        warn "No requirements.txt found at $REQ"
      fi
    fi
  fi
  rm -f "$TMP" || true
else
  warn "No Python venv found in standard locations: ${CANDIDATES[*]}"
fi

# Docker/Container checks
if command -v docker >/dev/null 2>&1; then
  info "Checking known docker containers"
  KNOWN=(aiagent_web aiagent_worker aiagent-redis aiagent-web aiagent-worker)
  for c in "${KNOWN[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
      info "Container $c running; checking health status"
      docker inspect --format '{{json .State}}' "$c" | sed -n '1,1p' | tee -a "$LOGFILE"
      # try a quick ping if redis
      if [ "$c" = "aiagent-redis" ] || [ "$c" = "aiagent_redis" ]; then
        if docker exec "$c" redis-cli ping >/dev/null 2>&1; then info "Redis container responded to PING"; else warn "Redis ping failed"
        fi
    fi
  done
else
  info "Docker not installed; skipping docker checks"
fi

# Optional extended checks
if [ "$FULL" = "yes" ]; then
  info "Running extended checks..."
  # check ports
  for p in 8000 6379; do
    if ss -ltn | awk '{print $4}' | grep -q ":$p$"; then info "Port $p is listening"; else warn "Port $p not listening"; fi
  done
fi

# If severe problems and emergency tool exists, offer to run it
SEVERE=0
if grep -q "fail\|error\|not present" "$LOGFILE" >/dev/null 2>&1; then SEVERE=1; fi

if [ $SEVERE -eq 1 ] && [ -x "$EMERGENCY_TOOL" ]; then
  if [ "$AUTO_FIX" = "yes" ] || [ "$NON_INTERACTIVE" = "yes" ]; then
    info "Running emergency repair tool: $EMERGENCY_TOOL --full-auto --non-interactive"
    run "bash \"$EMERGENCY_TOOL\" --full-auto --non-interactive || true"
  else
    warn "Doctor found issues. To attempt automated repair run: sudo $EMERGENCY_TOOL --full-auto --non-interactive"
  fi
else
  info "Doctor run finished. Log: $LOGFILE"
fi

exit 0

