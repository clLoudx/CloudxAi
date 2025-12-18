#!/usr/bin/env bash
# upgrade.sh - Safe upgrade script for AI Agent
# Usage: sudo ./upgrade.sh [--branch BRANCH] [--no-restart] [--dry-run] [--yes] [--help]
set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/var/backups/aiagent_upgrade_${TIMESTAMP}"
LOGFILE="/var/log/aiagent_upgrade_${TIMESTAMP}.log"
BRANCH="main"
NO_RESTART="no"
NON_INTERACTIVE="no"
DRY_RUN="no"

info(){ printf "[INFO] %s\n" "$*" | tee -a "$LOGFILE"; }
warn(){ printf "[WARN] %s\n" "$*" | tee -a "$LOGFILE" >&2; }
err(){ printf "[ERR] %s\n" "$*" | tee -a "$LOGFILE" >&2; exit 1; }
run(){ if [ "$DRY_RUN" = "yes" ]; then info "[DRY-RUN] $*"; else eval "$@" >> "$LOGFILE" 2>&1; fi; }

usage(){
  cat <<EOF
upgrade.sh - Upgrade AI Agent repo and artifacts

Usage:
  sudo ./upgrade.sh [options]

Options:
  --branch BRANCH      : git branch to checkout/pull (default: main)
  --no-restart         : do not restart services after upgrade
  --yes                : non-interactive confirm all
  --dry-run            : print actions but do not execute
  -h, --help           : show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2;;
    --no-restart) NO_RESTART="yes"; shift;;
    --yes|--non-interactive) NON_INTERACTIVE="yes"; shift;;
    --dry-run) DRY_RUN="yes"; shift;;
    -h|--help) usage;;
    *) warn "Unknown option: $1"; shift;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then err "Please run as root (sudo)"; fi

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
info "Starting upgrade (branch=$BRANCH dry-run=$DRY_RUN)"

confirm_or_abort(){
  if [ "$NON_INTERACTIVE" = "yes" ]; then return 0; fi
  read -r -p "$1 [y/N]: " ANS
  case "$ANS" in [Yy]*) return 0;; *) err "Aborted by user";; esac
}

# Step 1 - backup current state
info "Creating backup of current repo and systemd units -> $BACKUP_DIR"
run "mkdir -p \"$BACKUP_DIR\""
if [ -d "$REPO_ROOT" ]; then
  run "tar -czf \"$BACKUP_DIR/repo_${TIMESTAMP}.tgz\" -C \"$REPO_ROOT\" . || true"
fi
# copy systemd units
run "mkdir -p \"$BACKUP_DIR/systemd\""
for u in aiagent-app.service aiagent-rq.service aiagent.service; do
  if [ -f /etc/systemd/system/$u ]; then run "cp -a /etc/systemd/system/$u \"$BACKUP_DIR/systemd/\" || true"; fi
done

# Step 2 - attempt upgrade via git if repo exists
if [ -d "$REPO_ROOT/.git" ]; then
  info "Pulling latest changes from git (branch: $BRANCH)"
  run "cd \"$REPO_ROOT\" && git fetch --all --prune >> \"$LOGFILE\" 2>&1"
  # attempt to fast-forward
  run "cd \"$REPO_ROOT\" && git checkout \"$BRANCH\" >> \"$LOGFILE\" 2>&1 || true"
  run "cd \"$REPO_ROOT\" && git pull --ff-only origin \"$BRANCH\" >> \"$LOGFILE\" 2>&1 || true"
else
  warn "Not a git repo; skipping git pull. If you want to upgrade, place new archive in $REPO_ROOT and run build scripts manually"
fi

# Step 3 - run repo helper upgrade/build scripts if present
if [ -f "$REPO_ROOT/generate_devops_and_files.sh" ] && [ -x "$REPO_ROOT/generate_devops_and_files.sh" ]; then
  info "Running generate_devops_and_files.sh"
  run "bash \"$REPO_ROOT/generate_devops_and_files.sh\" --auto || true"
fi

if [ -f "$REPO_ROOT/build_and_bundle.sh" ] && [ -x "$REPO_ROOT/build_and_bundle.sh" ]; then
  info "Running build_and_bundle.sh"
  run "bash \"$REPO_ROOT/build_and_bundle.sh\" || true"
fi

# Step 4 - update python venv if requirements changed
# Support both paths for migration compatibility
if [ -d "/opt/ai-agent/venv" ]; then
  VENV_DIR="${VENV_DIR:-/opt/ai-agent/venv}"
elif [ -d "/opt/aiagent/venv" ]; then
  VENV_DIR="${VENV_DIR:-/opt/aiagent/venv}"
  warn "Using legacy venv path /opt/aiagent/venv. Consider migrating to /opt/ai-agent/venv"
else
  VENV_DIR="${VENV_DIR:-/opt/ai-agent/venv}"
fi
REQ_FILE="$REPO_ROOT/requirements.txt"
if [ -f "$REQ_FILE" ]; then
  if [ ! -d "$VENV_DIR" ]; then
    info "Creating venv at $VENV_DIR"
    run "python3 -m venv \"$VENV_DIR\" || true"
  fi
  info "Installing Python dependencies from $REQ_FILE"
  run "\"$VENV_DIR/bin/pip\" install --upgrade pip setuptools wheel || true"
  run "\"$VENV_DIR/bin/pip\" install -r \"$REQ_FILE\" || true"
fi

# Step 5 - rebuild docker images if present
if [ -f "$REPO_ROOT/Dockerfile" ] || [ -f "$REPO_ROOT/Dockerfile.worker" ]; then
  if command -v docker >/dev/null 2>&1; then
    info "Rebuilding docker images"
    if [ -f "$REPO_ROOT/Dockerfile" ]; then run "docker build -f \"$REPO_ROOT/Dockerfile\" -t aiagent_web:latest \"$REPO_ROOT\" || true"; fi
    if [ -f "$REPO_ROOT/Dockerfile.worker" ]; then run "docker build -f \"$REPO_ROOT/Dockerfile.worker\" -t aiagent_worker:latest \"$REPO_ROOT\" || true"; fi
  else
    warn "Docker not available; skipping image rebuild"
  fi
fi

# Step 6 - restart services (unless requested otherwise)
if [ "$NO_RESTART" = "no" ]; then
  info "Restarting systemd services (if present)"
  for u in aiagent-app.service aiagent-rq.service aiagent.service; do
    if systemctl list-unit-files | grep -q "^${u}"; then
      run "systemctl daemon-reload || true"
      run "systemctl restart \"$u\" || true"
      run "systemctl enable \"$u\" || true"
    fi
  done
fi

info "Upgrade finished. Backups available at: $BACKUP_DIR"
exit 0

