#!/usr/bin/env bash
#
# aiagent_doctor.sh — PRO Edition (Deep Repair & Diagnostics)
#
# Behavior:
#  - Default: auto-fix non-critical issues at start (network, permissions, minor venv fixes)
#  - Reports critical issues and suggests manual actions
#  - Flags:
#      --manual-only   : only scan, no fixes
#      --full-auto     : auto-fix everything (including critical)
#      --no-auto       : scan and print (same as --manual-only)
#      --auto-repair-dpkg yes|no : allow automatic dpkg repair (default: ask)
#      --output <file> : write JSON report (default: /var/log/aiagent-doctor-report.json)
#      --quiet         : reduce stdout (still logs)
#
set -o errexit
set -o nounset
set -o pipefail

# Colors & helpers
RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; CYAN="\033[1;36m"; NC="\033[0m"
info(){ [ "$QUIET" = "yes" ] || echo -e "${BLUE}➤${NC} $*"; } 
ok(){ [ "$QUIET" = "yes" ] || echo -e "${GREEN}✔${NC} $*"; } 
warn(){ echo -e "${YELLOW}⚠${NC} $*" >&2; } 
err(){ echo -e "${RED}✘${NC} $*" >&2; }
section(){ [ "$QUIET" = "yes" ] || echo -e "\n${CYAN}========== $* ==========${NC}\n"; }

# Paths and defaults
TARGET="/opt/ai-agent"
ENV_DIR="/etc/ai-agent"
ENV_FILE="$ENV_DIR/env"
VENV="$TARGET/venv"
LOGFILE="/var/log/aiagent-doctor.log"
REPORT="/var/log/aiagent-doctor-report.json"
DPKG_REPAIR_TOOL="./tools/dpkg-emergency-repair.sh"   # adjust if placed elsewhere
AUTO_FIX_NONCRITICAL="yes"   # auto-fix non-critical by default
FULL_AUTO="no"
MANUAL_ONLY="no"
AUTO_REPAIR_DPKG="ask"
QUIET="no"

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --manual-only|--no-auto) MANUAL_ONLY="yes"; AUTO_FIX_NONCRITICAL="no"; shift ;;
    --full-auto) FULL_AUTO="yes"; AUTO_FIX_NONCRITICAL="yes"; AUTO_REPAIR_DPKG="yes"; shift ;;
    --auto-repair-dpkg) AUTO_REPAIR_DPKG="$2"; shift 2;;
    --output) REPORT="$2"; shift 2;;
    --quiet) QUIET="yes"; shift;;
    -h|--help) cat <<EOF
Usage: $0 [--manual-only|--full-auto] [--auto-repair-dpkg yes|no|ask] [--output /path] [--quiet]
Options:
  --manual-only / --no-auto   : scan only; do not perform fixes
  --full-auto                 : attempt to auto-fix critical issues (use with caution)
  --auto-repair-dpkg <yes/no/ask> : behavior for dpkg repair when corruption is detected (default: ask)
  --output <file>             : write JSON report (default: $REPORT)
  --quiet                     : reduce stdout, still writes logs and report
EOF
  exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then err "Run with sudo"; exit 1; fi
mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$REPORT")"
touch "$LOGFILE"
# simple logger
log(){ echo "[$(date --iso-8601=seconds)] $*" | tee -a "$LOGFILE"; }

section "AI Agent Doctor — PRO (deep diagnostics + repair)"
log "Doctor started: auto_fix_noncritical=$AUTO_FIX_NONCRITICAL full_auto=$FULL_AUTO manual_only=$MANUAL_ONLY auto_repair_dpkg=$AUTO_REPAIR_DPKG"

# Helper to run but capture failures
_safe_run(){
  if eval "$1"; then
    return 0
  else
    log "COMMAND_FAILED: $1"
    return 1
  fi
}

safe_backup(){ local f="$1"; [ -e "$f" ] && cp -a "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"; }

# --- Non-critical auto-fixes (safe)
if [ "$MANUAL_ONLY" = "no" ] && [ "$AUTO_FIX_NONCRITICAL" = "yes" ]; then
  section "Auto-fix: Non-critical (safe) items"
  log "Ensuring /etc/ai-agent directory and perms"
  if [ ! -d "$ENV_DIR" ]; then
    mkdir -p "$ENV_DIR"
    chmod 750 "$ENV_DIR"
    chown root:root "$ENV_DIR"
    log "Created $ENV_DIR with 750 perms"
  fi
  if [ -f "$ENV_FILE" ]; then
    chmod 600 "$ENV_FILE" || true
    log "Normalized perms on $ENV_FILE"
  fi
  ok "Env dir & file perms normalized (safe)"

  log "Cleaning stale temporary files (safe)"
  rm -rf /tmp/aiagent_* 2>/dev/null || true
  ok "Temp cleanup done"

  # fix simple permission issues in app dir (safe)
  if [ -d "$TARGET" ]; then
    OWNER=$(stat -c "%U" "$TARGET" 2>/dev/null || echo root)
    if [ "$OWNER" != "aiagent" ]; then
      warn "Directory $TARGET not owned by aiagent; attempting safe chown (may require review)"
      chown -R aiagent:aiagent "$TARGET" 2>/dev/null || true
      ok "Ownership attempted on $TARGET"
    fi
  fi
fi

# --- Begin deep diagnostics
section "Diagnostic checks (full scan)"
log "Collecting diagnostics..."

# function to check for apt/dpkg locks and dpkg status
check_dpkg_health(){
  local issues=()
  # locks
  for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
    if [ -e "$lock" ]; then
      issues+=("lock:$lock")
    fi
  done
  # dpkg audit / broken packages
  set +e
  dpkg_output=$(dpkg --audit 2>&1 || true)
  dpkg_rc=$?
  set -e
  if [ -n "$dpkg_output" ]; then
    # dpkg --audit prints packages in an inconsistent state
    issues+=("dpkg_audit")
  fi
  # try a safe parse of dpkg status
  if ! dpkg -l >/dev/null 2>&1; then
    issues+=("dpkg_unreadable")
  fi
  echo "${issues[@]}"
}

# Gather checks
ENV_ISSUES=()
if [ ! -f "$ENV_FILE" ]; then
  ENV_ISSUES+=("env_missing")
  warn "Environment file $ENV_FILE missing"
else
  OPENAI_KEY=$(grep -E '^OPENAI_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  if [ -z "$OPENAI_KEY" ]; then
    ENV_ISSUES+=("openai_key_missing")
    warn "OPENAI_API_KEY not set in $ENV_FILE"
  fi
fi

# Python venv and modules check
PY_ISSUES=()
if [ ! -x "$VENV/bin/python" ]; then
  PY_ISSUES+=("venv_missing")
  warn "Python venv missing at $VENV"
else
  # check core modules
  missing_mods=""
  for m in flask redis rq requests; do
    if ! "$VENV/bin/python" -c "import importlib,sys; sys.exit(0 if importlib.util.find_spec('$m') else 1)"; then
      missing_mods="${missing_mods}${m},"
    fi
  done
  if [ -n "$missing_mods" ]; then
    # trim trailing comma
    missing_mods=${missing_mods%,}
    PY_ISSUES+=("python_missing_modules:${missing_mods}")
    warn "Python missing modules: ${missing_mods}"
  fi
fi

# dpkg health
DPKG_ISSUES_RAW=$(check_dpkg_health || true)
DPKG_ISSUES=()
if [ -n "$DPKG_ISSUES_RAW" ]; then
  # split into array
  read -r -a tmparr <<< "$DPKG_ISSUES_RAW"
  for i in "${tmparr[@]}"; do DPKG_ISSUES+=("$i"); done
  warn "dpkg/apt issues detected: ${DPKG_ISSUES[*]}"
fi

# Redis check
REDIS_OK="no"
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q '^aiagent-redis$'; then
  if docker exec aiagent-redis redis-cli ping >/dev/null 2>&1; then REDIS_OK="yes"; fi
elif command -v redis-cli >/dev/null 2>&1; then
  if redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then REDIS_OK="yes"; fi
fi
if [ "$REDIS_OK" = "no" ]; then warn "Redis not responding"; fi

# Systemd units
SVC_ISSUES=()
if systemctl list-unit-files | grep -q '^aiagent-app.service'; then
  if ! systemctl is-active --quiet aiagent-app.service; then SVC_ISSUES+=("app_service_inactive"); warn "aiagent-app.service inactive"; fi
else
  SVC_ISSUES+=("app_service_missing"); warn "aiagent-app.service not installed"
fi
if systemctl list-unit-files | grep -q '^aiagent-rq.service'; then
  if ! systemctl is-active --quiet aiagent-rq.service; then SVC_ISSUES+=("worker_service_inactive"); warn "aiagent-rq.service inactive"; fi
else
  SVC_ISSUES+=("worker_service_missing"); warn "aiagent-rq.service not installed"
fi

# ports
PORT_8000="no"; PORT_6379="no"
if ss -ltn | awk '{print $4}' | grep -q ':8000$'; then PORT_8000="yes"; ok "Port 8000 is listening"; else warn "Port 8000 not listening"; fi
if ss -ltn | awk '{print $4}' | grep -q ':6379$'; then PORT_6379="yes"; fi

# disk & memory
FREE_KB=$(df --output=avail / | tail -1 2>/dev/null || echo 0)
FREE_GB=$((FREE_KB/1024/1024))
MEM_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_MB=$((MEM_KB/1024))
if [ "$FREE_GB" -lt 1 ]; then warn "Low disk: <1GB available"; fi
if [ "$MEM_MB" -lt 256 ]; then warn "Low memory: <256MB available"; fi

# git status (if repo present)
GIT_DIR_ISSUE="no"
if [ -d "$TARGET/.git" ]; then
  if ! git -C "$TARGET" status --porcelain >/dev/null 2>&1; then GIT_DIR_ISSUE="yes"; warn "Git status unreadable in $TARGET"; fi
fi

# ownership of target
OWNER_OK="yes"
if [ -d "$TARGET" ]; then
  OWNER=$(stat -c "%U" "$TARGET" 2>/dev/null || echo root)
  if [ "$OWNER" != "aiagent" ]; then OWNER_OK="no"; warn "Owner of $TARGET is $OWNER (expected aiagent)"
  fi
fi

# Build JSON report (simple, no jq)
timestamp="$(date --iso-8601=seconds)"
report_tmp="$(mktemp)"
cat > "$report_tmp" <<JSON
{
  "timestamp": "$timestamp",
  "target": "$TARGET",
  "env_file_exists": $( [ -f "$ENV_FILE" ] && echo "true" || echo "false" ),
  "env_issues": ["$(printf "%s" "${ENV_ISSUES[*]}" | sed 's/ /\",\"/g')"],
  "python_issues": ["$(printf "%s" "${PY_ISSUES[*]}" | sed 's/ /\",\"/g')"],
  "dpkg_issues": ["$(printf "%s" "${DPKG_ISSUES[*]}" | sed 's/ /\",\"/g')"],
  "redis_ok": "$REDIS_OK",
  "service_issues": ["$(printf "%s" "${SVC_ISSUES[*]}" | sed 's/ /\",\"/g')"],
  "ports": {"8000":"$PORT_8000","6379":"$PORT_6379"},
  "disk_free_gb": $FREE_GB,
  "mem_free_mb": $MEM_MB,
  "owner_ok": "$OWNER_OK",
  "git_dir_issue": "$GIT_DIR_ISSUE"
}
JSON
# pretty up arrays with empty elements removed
python3 - <<PY > "$REPORT" 2>/dev/null || cat "$report_tmp" > "$REPORT"
import json,sys
r=json.load(open("$report_tmp"))
# normalize lists (remove empty strings)
for k in ("env_issues","python_issues","dpkg_issues","service_issues"):
    r[k]=[x for x in r[k] if x!='' and x!=' ']
json.dump(r, open("$REPORT","w"), indent=2)
PY
rm -f "$report_tmp"
ok "Report written to $REPORT"
log "Diagnostics collected"

# --- Decide next actions based on issues
CRITICAL_ISSUES=()
[ ${#ENV_ISSUES[@]} -gt 0 ] && CRITICAL_ISSUES+=("${ENV_ISSUES[@]}")
[ ${#PY_ISSUES[@]} -gt 0 ] && CRITICAL_ISSUES+=("${PY_ISSUES[@]}")
[ ${#DPKG_ISSUES[@]} -gt 0 ] && CRITICAL_ISSUES+=("${DPKG_ISSUES[@]}")
[ ${#SVC_ISSUES[@]} -gt 0 ] && CRITICAL_ISSUES+=("${SVC_ISSUES[@]}")

if [ ${#CRITICAL_ISSUES[@]} -eq 0 ]; then
  section "No critical issues detected"
  ok "System looks healthy (or issues are only non-critical)."
  exit 0
fi

section "Critical issues detected (summary)"
for i in "${CRITICAL_ISSUES[@]}"; do warn " - $i"; done

# If dpkg issues are present, propose / run repair
if printf '%s\n' "${DPKG_ISSUES[@]}" | grep -qE "lock:|dpkg_audit|dpkg_unreadable"; then
  warn "Detected dpkg/apt corruption or locks — repair recommended."
  if [ "$AUTO_REPAIR_DPKG" = "yes" ] || [ "$FULL_AUTO" = "yes" ]; then
    # auto-run repair
    if [ -x "$DPKG_REPAIR_TOOL" ]; then
      section "Running dpkg emergency repair (auto)"
      log "Invoking $DPKG_REPAIR_TOOL (auto)"
      if "$DPKG_REPAIR_TOOL"; then
        ok "dpkg emergency repair completed (auto). Re-run doctor to validate."
      else
        warn "dpkg repair tool returned non-zero. Please inspect $LOGFILE and the tool output."
      fi
    else
      warn "dpkg repair tool not found or not executable at $DPKG_REPAIR_TOOL"
    fi
  elif [ "$AUTO_REPAIR_DPKG" = "ask" ] && [ "$MANUAL_ONLY" = "no" ]; then
    # interactive prompt
    if [ "$QUIET" != "yes" ]; then
      if confirm "Run dpkg emergency repair now using $DPKG_REPAIR_TOOL? (recommended)"; then
        if [ -x "$DPKG_REPAIR_TOOL" ]; then
          section "Running dpkg emergency repair (interactive)"
          "$DPKG_REPAIR_TOOL" || warn "Repair tool returned failure"
        else
          warn "dpkg repair tool not found/executable: $DPKG_REPAIR_TOOL"
        fi
      else
        warn "User declined dpkg repair; manual fix required."
      fi
    else
      warn "Quiet mode, and AUTO_REPAIR_DPKG=ask — skipping automatic dpkg repair. Re-run doctor with --auto-repair-dpkg yes or run the tool manually."
    fi
  else
    warn "AUTO_REPAIR_DPKG is set to '$AUTO_REPAIR_DPKG' — not running repair automatically."
  fi
fi

# If python modules missing, attempt venv fixes when FULL_AUTO
if printf '%s\n' "${PY_ISSUES[@]}" | grep -q "venv_missing\|python_missing_modules"; then
  if [ "$FULL_AUTO" = "yes" ]; then
    section "FULL-AUTO: attempting venv rebuild & pip install (may take time)"
    log "Recreating venv and reinstalling requirements"
    safe_backup "$VENV"
    python3 -m venv "$VENV" || warn "venv creation failed"
    "$VENV/bin/pip" install --upgrade pip setuptools wheel || warn "pip upgrade failed"
    if [ -f "$TARGET/requirements.txt" ]; then
      "$VENV/bin/pip" install -r "$TARGET/requirements.txt" || warn "pip install (requirements) failed"
    fi
    ok "Venv repair attempted; re-run doctor to validate"
  else
    echo ""
    echo "Manual fix for Python modules:"
    echo "  source $VENV/bin/activate"
    echo "  pip install -r $TARGET/requirements.txt"
  fi
fi

# Service issues
if printf '%s\n' "${SVC_ISSUES[@]}" | grep -qE "app_service_missing|worker_service_missing|inactive"; then
  echo ""
  echo "Service suggestions:"
  echo "  - Inspect journal for aiagent-app and aiagent-rq:"
  echo "     sudo journalctl -u aiagent-app -n 200 --no-pager"
  echo "     sudo journalctl -u aiagent-rq -n 200 --no-pager"
  echo "  - If unit missing, copy templates from $TARGET/deploy/systemd/ or use installer to generate systemd units"
  if [ "$FULL_AUTO" = "yes" ]; then
    section "FULL-AUTO: attempting to recreate systemd units from $TARGET/deploy/systemd (if present)"
    if [ -f "$TARGET/deploy/systemd/ai-agent-app.service" ]; then
      cp -a "$TARGET/deploy/systemd/ai-agent-app.service" /etc/systemd/system/aiagent-app.service || true
    fi
    if [ -f "$TARGET/deploy/systemd/ai-agent-worker.service" ]; then
      cp -a "$TARGET/deploy/systemd/ai-agent-worker.service" /etc/systemd/system/aiagent-rq.service || true
    fi
    systemctl daemon-reload || true
    systemctl enable --now aiagent-app.service aiagent-rq.service || true
    ok "Attempted to recreate and start systemd units"
  fi
fi

section "Doctor completed (summary)"
log "Doctor finished; report at $REPORT"
echo ""
echo "Report: $REPORT"
echo "Log: $LOGFILE"
if [ "$FULL_AUTO" = "yes" ]; then
  ok "FULL-AUTO mode performed actions; re-run doctor to validate final state."
else
  echo ""
  echo "To auto-repair dpkg issues now run:"
  echo "  sudo $DPKG_REPAIR_TOOL"
  echo "Or re-run this doctor with --full-auto to attempt automated fixes (caution)."
fi

# Exit non-zero to indicate there were critical issues (unless full-auto attempted repair)
if [ "$FULL_AUTO" = "yes" ]; then
  exit 0
else
  # return 2 when critical issues found
  exit 2
fi

