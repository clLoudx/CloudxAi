#!/usr/bin/env bash
#
# tools/emergency-total-repair.sh
#
# Ultra PRO Emergency Repair: dpkg/apt + python-core + venv + systemd + wget-fallback + self-heal
#
# Place in project/tools/, chmod +x, run as root:
#   sudo ./tools/emergency-total-repair.sh --full-auto --self-heal --restart-agent
#
set -o errexit
set -o nounset
set -o pipefail

## ---------------------------
## Configuration (tune as needed)
## ---------------------------
LOG="/var/log/aiagent-emergency-repair.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
exec 3>>"$LOG"

# Defaults
TARGET_DIR="/opt/ai-agent"
VENV_PATH="$TARGET_DIR/venv"
AI_USER="aiagent"
APP_SERVICE="aiagent-app.service"
WORKER_SERVICE="aiagent-rq.service"
DPKG_REPAIR_TOOL="./tools/dpkg-emergency-repair.sh"   # kept for compatibility if you want to call it
RETRY_BASE_SEC=4
RETRY_FACTOR=2
RETRY_MAX_SEC=300
MAX_SELF_HEAL_CYCLES=10
APT_WATCHDOG_TIMEOUT=90
NETWORK_TEST_URL="https://mirrors.ubuntu.com/mirrors.txt"
FALLBACK_MIRRORS=( "http://archive.ubuntu.com/ubuntu/" "http://ports.ubuntu.com/ubuntu/" "http://security.ubuntu.com/ubuntu/" )

# apt packages we may need to reinstall (D list)
APT_PACKAGES_CORE=( python3 python3-venv python3-minimal python3-distutils python3-dev build-essential libssl-dev libffi-dev wget apt-transport-https ca-certificates gnupg lsb-release )

# CLI flags (will be set by parse_args)
FULL_AUTO="no"
MANUAL_ONLY="no"
SELF_HEAL="no"
RESTART_AGENT="no"
REPAIR_SYSTEMD="no"
WGET_FALLBACK="no"
NON_INTERACTIVE="no"
VERBOSE="no"

## ---------------------------
## Logging / UI helpers
## ---------------------------
COLOR_RED="\033[1;31m"; COLOR_GREEN="\033[1;32m"; COLOR_YELLOW="\033[1;33m"; COLOR_BLUE="\033[1;34m"; COLOR_CYAN="\033[1;36m"; COLOR_NC="\033[0m"
_info(){ printf "${COLOR_BLUE}➤${COLOR_NC} %s\n" "$*"; echo "[$(date --iso-8601=seconds)] INFO: $*" >&3; }
_ok(){ printf "${COLOR_GREEN}✔${COLOR_NC} %s\n" "$*"; echo "[$(date --iso-8601=seconds)] OK: $*" >&3; }
_warn(){ printf "${COLOR_YELLOW}⚠${COLOR_NC} %s\n" "$*"; echo "[$(date --iso-8601=seconds)] WARN: $*" >&3; }
_err(){ printf "${COLOR_RED}✘${COLOR_NC} %s\n" "$*" >&3; }
_debug(){ [ "$VERBOSE" = "yes" ] && echo "[$(date --iso-8601=seconds)] DEBUG: $*" >&3; }

confirm(){ 
  if [ "$NON_INTERACTIVE" = "yes" ]; then return 0; fi
  read -p "$1 [y/N]: " yn
  [[ "$yn" =~ ^[Yy]$ ]]
}

safe_backup(){
  local src="$1"
  if [ -e "$src" ]; then
    local bdir="/opt/ai-agent-backups"
    mkdir -p "$bdir"
    local target="$bdir/$(basename "$src").bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "$src" "$target" && _info "Backed up $src → $target"
  fi
}

retry_cmd(){
  # usage: retry_cmd max_attempts sleep_base cmd...
  local max="$1"; shift
  local base="$1"; shift
  local attempt=0
  local delay="$base"
  while [ $attempt -lt $max ]; do
    attempt=$((attempt+1))
    if eval "$*"; then
      return 0
    fi
    _warn "Command failed (attempt $attempt/$max): will sleep ${delay}s and retry"
    sleep "$delay"
    delay=$(( delay * RETRY_FACTOR ))
    [ $delay -gt $RETRY_MAX_SEC ] && delay=$RETRY_MAX_SEC
  done
  return 1
}

retry_forever_with_backoff(){
  # usage: retry_forever_with_backoff base_seconds cmd...
  local delay="$1"; shift
  local attempt=0
  while true; do
    attempt=$((attempt+1))
    if eval "$*"; then
      _debug "Success on attempt $attempt"
      return 0
    fi
    _warn "Attempt #$attempt failed; sleeping ${delay}s before retry"
    sleep $delay
    delay=$(( delay * RETRY_FACTOR ))
    [ $delay -gt $RETRY_MAX_SEC ] && delay=$RETRY_MAX_SEC
  done
}

## ---------------------------
## Arg parsing
## ---------------------------
usage(){
  cat <<EOF
emergency-total-repair.sh — FULL Emergency Repair for AI Agent

Usage:
  sudo ./emergency-total-repair.sh [options]

Options:
  --full-auto           : automatically attempt critical fixes
  --manual-only|--no-auto : only scan and print actions
  --self-heal           : repeat repair cycles until fixed (max cycles)
  --restart-agent       : restart aiagent services at the end
  --repair-systemd      : recreate missing systemd units from templates in repo
  --wget-fallback       : enable wget fallback for .deb packages
  --venv-path PATH      : path to venv (default: $VENV_PATH)
  --target PATH         : project root (default: $TARGET_DIR)
  --non-interactive     : assume yes to all prompts
  --verbose             : more logging to logfile
  -h, --help            : show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --full-auto) FULL_AUTO="yes"; shift;;
    --manual-only|--no-auto) MANUAL_ONLY="yes"; FULL_AUTO="no"; shift;;
    --self-heal) SELF_HEAL="yes"; shift;;
    --restart-agent) RESTART_AGENT="yes"; shift;;
    --repair-systemd) REPAIR_SYSTEMD="yes"; shift;;
    --wget-fallback) WGET_FALLBACK="yes"; shift;;
    --venv-path) VENV_PATH="$2"; shift 2;;
    --target) TARGET_DIR="$2"; shift 2;;
    --non-interactive) NON_INTERACTIVE="yes"; shift;;
    --verbose) VERBOSE="yes"; shift;;
    -h|--help) usage;;
    *) _warn "Unknown option: $1"; shift;;
  esac
done

_info "Emergency Repair started"
_info "Target: $TARGET_DIR  Venv: $VENV_PATH  FULL_AUTO=$FULL_AUTO  SELF_HEAL=$SELF_HEAL  WGET_FALLBACK=$WGET_FALLBACK"

if [ "$(id -u)" -ne 0 ]; then _err "Please run as root (sudo)"; exit 1; fi

## ---------------------------
## Environment facts & timeline snapshot
## ---------------------------
snapshot_state(){
  local out="/var/log/aiagent-repair-state-$(date +%Y%m%d_%H%M%S).json"
  jq -n \
    --arg ts "$(date --iso-8601=seconds)" \
    --arg target "$TARGET_DIR" \
    --arg venv "$VENV_PATH" \
    --arg arch "$(dpkg --print-architecture 2>/dev/null || uname -m)" \
    '{timestamp:$ts,target:$target,venv:$venv,arch:$arch}' > "$out"
  _info "Snapshot written to $out"
}

snapshot_state

## ---------------------------
## Low-level helpers needed by repairs
## ---------------------------
kill_apt_dpkg_procs(){
  _info "Searching for apt/dpkg processes"
  local pids
  pids=$(pgrep -af 'apt|dpkg' | awk '{print $1}' || true)
  if [ -n "$pids" ]; then
    _warn "Found apt/dpkg PIDs: $pids -> killing (SIGKILL)"
    for p in $pids; do kill -9 "$p" >/dev/null 2>&1 || true; done
    sleep 1
  else
    _debug "No apt/dpkg processes found"
  fi
}

remove_lock_files(){
  local locks=(/var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock)
  for l in "${locks[@]}"; do
    if [ -e "$l" ]; then
      _warn "Removing lock file: $l"
      rm -f "$l" || true
    fi
  done
}

safe_dpkg_configure(){
  _info "Running: dpkg --configure -a"
  set +e; dpkg --configure -a >> "$LOG" 2>&1; local rc=$?; set -e
  if [ $rc -eq 0 ]; then _ok "dpkg --configure -a OK"; else _warn "dpkg --configure -a rc=$rc"; fi
}

safe_apt_fix(){
  _info "Running: apt-get install -f -y"
  set +e; apt-get install -f -y >> "$LOG" 2>&1; local rc=$?; set -e
  if [ $rc -eq 0 ]; then _ok "apt-get install -f OK"; else _warn "apt-get install -f rc=$rc"; fi
}

rebuild_apt_lists(){
  _info "Rebuilding apt lists (move old lists -> backup)"
  if [ -d /var/lib/apt/lists ]; then mv /var/lib/apt/lists "/var/lib/apt/lists.bak.$(date +%s)" || true; fi
  mkdir -p /var/lib/apt/lists/partial
  apt-get clean >> "$LOG" 2>&1 || true
  # Try a robust update with mirror rotation (simple)
  local tried=0
  for m in "${FALLBACK_MIRRORS[@]}"; do
    _info "Trying apt-get update with mirror: $m"
    cat >/etc/apt/sources.list <<EOF
deb ${m} $(lsb_release -cs 2>/dev/null || echo jammy) main universe restricted multiverse
deb ${m} $(lsb_release -cs 2>/dev/null || echo jammy)-updates main universe restricted multiverse
deb ${m} $(lsb_release -cs 2>/dev/null || echo jammy)-security main universe restricted multiverse
EOF
    set +e
    apt-get update -o Acquire::Retries=3 >> "$LOG" 2>&1
    local rc=$?
    set -e
    if [ $rc -eq 0 ]; then _ok "apt-get update OK with mirror $m"; return 0; fi
    tried=$((tried+1))
  done
  _warn "apt-get update failed on fallback mirrors"
  return 1
}

dpkg_repair_full(){
  _info "=== DPKG / APT FULL EMERGENCY REPAIR ==="
  kill_apt_dpkg_procs
  remove_lock_files
  safe_dpkg_configure
  safe_apt_fix
  rebuild_apt_lists
  _info "DPKG/APT repair pass complete"
}

## ---------------------------
## WGET fallback helper (for apt .deb fallback)
## ---------------------------
collect_deb_uris(){
  # collects URIs for a list of packages and returns file path containing URIs
  local pkglist=("$@")
  local tmpdir
  tmpdir=$(mktemp -d -t aiagent-deb-XXXX)
  local urifile="$tmpdir/uris.txt"
  touch "$urifile"
  _info "Collecting .deb URIs for packages: ${pkglist[*]}"
  for p in "${pkglist[@]}"; do
    _debug "apt-get --print-uris for $p"
    set +e
    apt-get --print-uris -y install --allow-unauthenticated "$p" 2>>"$LOG" | awk -F"'" '/http/ {print $2}' >> "$urifile"
    local rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      _warn "apt-get --print-uris failed for $p (rc=$rc). Try apt download"
      set +e
      apt download "$p" >> "$LOG" 2>&1 || true
      set -e
    fi
  done
  sort -u "$urifile" -o "$urifile" || true
  if [ -s "$urifile" ]; then
    _info "Collected URIs: $(wc -l < "$urifile") entries"
    echo "$urifile"
    return 0
  else
    _warn "No URIs discovered"
    rm -rf "$tmpdir"
    return 1
  fi
}

wget_and_install_debs(){
  local urifile="$1"
  local tmpdir
  tmpdir=$(dirname "$urifile")  # same tmpdir as collect
  _info "Downloading .debs listed in $urifile"
  while read -r url; do
    [ -z "$url" ] && continue
    local fname="$tmpdir/$(basename "$url")"
    local attempt=0
    local delay=$RETRY_BASE_SEC
    while [ $attempt -lt 8 ]; do
      attempt=$((attempt+1))
      _debug "wget attempt $attempt -> $url"
      if wget --tries=3 --timeout=30 -q -O "$fname" "$url"; then
        _ok "Downloaded $url -> $fname"
        break
      fi
      _warn "wget failed attempt $attempt for $url; sleeping $delay"
      sleep "$delay"
      delay=$(( delay * RETRY_FACTOR ))
      [ $delay -gt $RETRY_MAX_SEC ] && delay=$RETRY_MAX_SEC
    done
  done < "$urifile"

  _info "Installing downloaded debs with dpkg -i (best-effort order)"
  set +e
  dpkg -i "$tmpdir"/*.deb >> "$LOG" 2>&1 || true
  apt-get install -f -y >> "$LOG" 2>&1 || true
  set -e
  _ok "Wget fallback attempted (see $LOG)"
  return 0
}

## ---------------------------
## Python core reinstall + venv repair
## ---------------------------
python_core_repair(){
  _info "=== PYTHON CORE + VENV REPAIR ==="
  # Determine system python major/minor
  local pymaj
  pymaj=$(python3 -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))' 2>/dev/null || echo "3.10")
  _info "Detected python version: $pymaj"

  # Attempt to reinstall apt packages for python core
  _info "Reinstall core apt packages: ${APT_PACKAGES_CORE[*]}"
  set +e
  apt-get update -o Acquire::Retries=3 >> "$LOG" 2>&1 || true
  apt-get install --reinstall -y "${APT_PACKAGES_CORE[@]}" >> "$LOG" 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    _warn "apt reinstall of python core returned rc=$rc"
    if [ "$WGET_FALLBACK" = "yes" ]; then
      _info "Attempt wget fallback for python core packages"
      urifile=$(collect_deb_uris "${APT_PACKAGES_CORE[@]}" 2>/dev/null || true) || true
      if [ -n "$urifile" ]; then wget_and_install_debs "$urifile"; fi
    fi
  else
    _ok "Reinstalled python core packages via apt"
  fi

  # Ensure importlib.util exists (quick test)
  set +e
  python3 - <<'PY' 2>>"$LOG" || true
import importlib,sys
print("UTIL=" + str(hasattr(importlib, "util")))
PY
  set -e

  # Recreate venv if requested/needed
  if [ -d "$VENV_PATH" ]; then
    _info "Existing venv found at $VENV_PATH; backing up"
    safe_backup "$VENV_PATH"
    rm -rf "$VENV_PATH" || true
  fi

  _info "Creating venv at $VENV_PATH"
  python3 -m venv "$VENV_PATH" >> "$LOG" 2>&1 || { _warn "venv creation failed"; return 1; }
  _info "Upgrading pip/setuptools/wheel inside venv"
  "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel >> "$LOG" 2>&1 || _warn "pip upgrade failed"

  # If project requirements exist, install them robustly
  local reqf="$TARGET_DIR/requirements.txt"
  if [ -f "$reqf" ]; then
    _info "Installing project requirements from $reqf"
    # attempt limited tries, then infinite retry
    local attempt=1; local max=3
    while [ $attempt -le $max ]; do
      if "$VENV_PATH/bin/pip" install --no-cache-dir -r "$reqf" >> "$LOG" 2>&1; then
        _ok "pip install completed (attempt $attempt)"
        break
      fi
      _warn "pip install failed (attempt $attempt). Inspecting logs for build deps..."
      # detect rust & python.h indicators
      if grep -iE "rust|rustc|cargo" "$LOG" >/dev/null 2>&1; then
        _info "Installing rust toolchain via apt"
        apt-get install -y --no-install-recommends rustc cargo >> "$LOG" 2>&1 || true
      fi
      if grep -iE "fatal error: Python.h" "$LOG" >/dev/null 2>&1; then
        _info "Installing Python build headers"
        apt-get install -y --no-install-recommends build-essential python3-dev libssl-dev libffi-dev >> "$LOG" 2>&1 || true
      fi
      attempt=$((attempt+1))
      sleep $((RETRY_BASE_SEC * attempt))
      if [ $attempt -gt $max ]; then
        _warn "Entering extended pip retry loop (network may be flaky). This may take long."
        retry_forever_with_backoff $RETRY_BASE_SEC "$VENV_PATH/bin/pip install --no-cache-dir -r \"$reqf\" >> \"$LOG\" 2>&1"
        break
      fi
    done
  else
    _warn "No requirements.txt found at $reqf"
  fi

  _ok "Python core & venv repair complete"
  return 0
}

## ---------------------------
## Systemd unit repair & recreation
## ---------------------------
repair_systemd_units(){
  _info "=== SYSTEMD UNIT CHECK & REPAIR ==="
  local missing=()
  for u in "$APP_SERVICE" "$WORKER_SERVICE"; do
    if systemctl list-unit-files | grep -q "^${u}"; then
      _debug "Unit $u exists"
      if ! systemctl is-enabled --quiet "$u"; then
        _warn "Unit $u exists but not enabled -> enabling"
        systemctl enable "$u" >> "$LOG" 2>&1 || true
      fi
    else
      _warn "Unit $u missing"
      missing+=("$u")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then _ok "No missing systemd units detected"; return 0; fi

  if [ "$REPAIR_SYSTEMD" = "no" ] && [ "$FULL_AUTO" != "yes" ]; then
    _warn "Missing units: ${missing[*]}. Use --repair-systemd or --full-auto to recreate from templates."
    return 1
  fi

  # Try to recreate units from repo templates under common paths
  local templates=(
    "$TARGET_DIR/deploy/systemd/ai-agent-app.service"
    "$TARGET_DIR/deploy/systemd/ai-agent-worker.service"
    "$TARGET_DIR/deploy/systemd/aiagent-app.service"
    "$TARGET_DIR/deploy/systemd/aiagent-rq.service"
    "$TARGET_DIR/systemd/aiagent-app.service"
    "$TARGET_DIR/systemd/aiagent-rq.service"
  )

  for want in "${missing[@]}"; do
    _info "Attempting to recreate $want from templates"
    found="no"
    for t in "${templates[@]}"; do
      if [ -f "$t" ]; then
        _info "Found template $t -> copying to /etc/systemd/system/$want"
        safe_backup "/etc/systemd/system/$want"
        cp -a "$t" "/etc/systemd/system/$want"
        found="yes"
        break
      fi
    done
    if [ "$found" = "no" ]; then
      _warn "No template found for $want in project; generating a best-effort service unit"
      # generate minimal templates (make them conservative)
      if [ "$want" = "$APP_SERVICE" ]; then
        cat >/etc/systemd/system/$APP_SERVICE <<EOF
[Unit]
Description=AI Agent Dashboard (generated)
After=network.target

[Service]
User=$AI_USER
WorkingDirectory=$TARGET_DIR/dashboard
EnvironmentFile=/etc/ai-agent/env
ExecStart=$VENV_PATH/bin/gunicorn dashboard.app:app -k eventlet -b 0.0.0.0:8000 --workers 2
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
      else
        cat >/etc/systemd/system/$WORKER_SERVICE <<EOF
[Unit]
Description=AI Agent RQ Worker (generated)
After=network.target

[Service]
User=$AI_USER
WorkingDirectory=$TARGET_DIR
EnvironmentFile=/etc/ai-agent/env
ExecStart=/bin/bash -lc "source $VENV_PATH/bin/activate; exec rq worker -u \${REDIS_URL:-redis://127.0.0.1:6379/0} default"
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
      fi
      _info "Generated $want"
    fi
  done

  systemctl daemon-reload >> "$LOG" 2>&1 || true
  for u in "${missing[@]}"; do
    _info "Enabling & starting $u"
    systemctl enable --now "$u" >> "$LOG" 2>&1 || _warn "systemctl enable/start $u returned non-zero"
  done

  _ok "Systemd unit repair pass complete"
}

## ---------------------------
## Final verification checks (report)
## ---------------------------
verify_all(){
  _info "=== FINAL VERIFICATION ==="
  local ok_count=0; local warn_count=0
  # dpkg healthy?
  if dpkg -l >/dev/null 2>&1; then _ok "dpkg database accessible"; ok_count=$((ok_count+1)); else _warn "dpkg database may be corrupted"; warn_count=$((warn_count+1)); fi

  # venv python checks
  if [ -x "$VENV_PATH/bin/python" ]; then
    # check importlib.util availability
    if "$VENV_PATH/bin/python" - <<'PY' 2>/dev/null
import importlib
print("UTIL="+str(hasattr(importlib,"util")))
PY
    then
      out=$("$VENV_PATH/bin/python" - <<'PY' 2>/dev/null
import importlib,sys
print("UTIL="+str(hasattr(importlib,"util")))
PY
)
      if echo "$out" | grep -q "UTIL=True"; then _ok "importlib.util present in venv"; ok_count=$((ok_count+1)); else _warn "importlib.util missing in venv"; warn_count=$((warn_count+1)); fi
    else
      _warn "Venv python import test failed"
      warn_count=$((warn_count+1))
    fi
  else
    _warn "Venv not present at $VENV_PATH"
    warn_count=$((warn_count+1))
  fi

  # services & ports
  if systemctl list-unit-files | grep -q "${APP_SERVICE}"; then
    if systemctl is-active --quiet "${APP_SERVICE}"; then _ok "$APP_SERVICE active"; ok_count=$((ok_count+1)); else _warn "$APP_SERVICE inactive"; warn_count=$((warn_count+1)); fi
  else
    _warn "$APP_SERVICE missing"; warn_count=$((warn_count+1)); fi

  if systemctl list-unit-files | grep -q "${WORKER_SERVICE}"; then
    if systemctl is-active --quiet "${WORKER_SERVICE}"; then _ok "$WORKER_SERVICE active"; ok_count=$((ok_count+1)); else _warn "$WORKER_SERVICE inactive"; warn_count=$((warn_count+1)); fi
  else
    _warn "$WORKER_SERVICE missing"; warn_count=$((warn_count+1)); fi

  # Redis check if present
  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^aiagent-redis$"; then
    if docker exec aiagent-redis redis-cli ping >/dev/null 2>&1; then _ok "Redis PONG"; ok_count=$((ok_count+1)); else _warn "Redis present but PING failed"; warn_count=$((warn_count+1)); fi
  else
    _warn "Redis container not running"
    warn_count=$((warn_count+1))
  fi

  _info "Verification summary: OKs=$ok_count  WARNs=$warn_count"
  return $warn_count
}

## ---------------------------
## Top-level recovery cycle
## ---------------------------
run_repair_cycle(){
  _info "=== REPAIR CYCLE START ==="

  # 1) dpkg/apt repair pass
  dpkg_repair_full

  # 2) python core + venv repair
  python_core_repair

  # 3) systemd repair (optional)
  if [ "$REPAIR_SYSTEMD" = "yes" ] || [ "$FULL_AUTO" = "yes" ]; then
    repair_systemd_units || _warn "systemd repair reported issues"
  else
    _debug "Skipping systemd auto-repair (disabled)"
  fi

  # 4) final verify
  verify_all
  local warn_count=$?
  if [ $warn_count -eq 0 ]; then
    _ok "Repair cycle reports ZERO warnings — considered success"
    return 0
  else
    _warn "Repair cycle reports $warn_count warnings"
    return 1
  fi
}

## ---------------------------
## Self-heal loop (optional)
## ---------------------------
if [ "$SELF_HEAL" = "yes" ]; then
  _info "Self-heal engaged: will attempt up to $MAX_SELF_HEAL_CYCLES cycles until success"
  cycle=0
  while [ $cycle -lt $MAX_SELF_HEAL_CYCLES ]; do
    cycle=$((cycle+1))
    _info "Self-heal cycle #$cycle"

    if run_repair_cycle; then
      _ok "Self-heal succeeded on cycle #$cycle"
      break
    fi

    _warn "Cycle #$cycle failed — sleeping before next attempt"
    sleep $(( RETRY_BASE_SEC * cycle ))
  done

  if [ $cycle -ge $MAX_SELF_HEAL_CYCLES ]; then
    _err "Self-heal exhausted ($MAX_SELF_HEAL_CYCLES cycles). Manual intervention required."
  fi
else
  if ! run_repair_cycle; then
    _warn "Single repair pass did not resolve all issues"
    if [ "$FULL_AUTO" = "yes" ]; then
      _warn "FULL_AUTO engaged but still warnings remain"
    fi
  fi
fi


## ---------------------------
## Optional restart of agent
## ---------------------------
if [ "$RESTART_AGENT" = "yes" ]; then
  _info "Restarting agent services: $APP_SERVICE, $WORKER_SERVICE"
  systemctl daemon-reload >> "$LOG" 2>&1 || true
  systemctl restart "$APP_SERVICE" >> "$LOG" 2>&1 || _warn "Failed restart $APP_SERVICE"
  systemctl restart "$WORKER_SERVICE" >> "$LOG" 2>&1 || _warn "Failed restart $WORKER_SERVICE"
  _ok "Restart attempts done (check journalctl for logs)"
fi

snapshot_state
_info "Emergency repair finished. See $LOG for full log, and /var/log/aiagent-repair-state-*.json for snapshots."
exit 0

