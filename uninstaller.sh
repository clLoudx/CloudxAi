#!/usr/bin/env bash
# uninstall.sh - Safe uninstaller for AI Agent
# Usage: sudo ./uninstall.sh [--preserve-data] [--remove-docker] [--yes] [--dry-run] [--help]
set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/var/backups/aiagent_uninstall_${TIMESTAMP}"
LOGFILE="/var/log/aiagent_uninstall_${TIMESTAMP}.log"
SYSTEMD_DIR="/etc/systemd/system"
ENV_DIR="/etc/ai-agent"
AI_USER="aiagent"
# Support both paths for migration compatibility
TARGET_DIR="/opt/ai-agent"   # canonical installation path (standardized)
TARGET_DIR_LEGACY="/opt/aiagent"   # legacy path (for migration)
KEEP_DATA="no"
REMOVE_DOCKER="no"
NON_INTERACTIVE="no"
DRY_RUN="no"

# helpers
info(){ printf "[INFO] %s\n" "$*" | tee -a "$LOGFILE"; }
warn(){ printf "[WARN] %s\n" "$*" | tee -a "$LOGFILE" >&2; }
err(){ printf "[ERR] %s\n" "$*" | tee -a "$LOGFILE" >&2; exit 1; }
run(){ if [ "$DRY_RUN" = "yes" ]; then info "[DRY-RUN] $*"; else eval "$@" >> "$LOGFILE" 2>&1; fi; }

usage(){
  cat <<EOF
uninstall.sh - Safe uninstaller for AI Agent

Usage:
  sudo ./uninstall.sh [options]

Options:
  --preserve-data      : keep persistent data (DB, logs, backups under /var/lib or /var/log)
  --remove-docker      : remove Docker containers and images related to aiagent
  --yes                : non-interactive, assume YES for confirmations
  --dry-run            : show actions but do not execute destructive steps
  -h, --help           : show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --preserve-data) KEEP_DATA="yes"; shift;;
    --remove-docker) REMOVE_DOCKER="yes"; shift;;
    --yes|--non-interactive) NON_INTERACTIVE="yes"; shift;;
    --dry-run) DRY_RUN="yes"; shift;;
    -h|--help) usage;;
    *) warn "Unknown option: $1"; shift;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then err "Please run as root (sudo)"; fi

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
info "Starting uninstaller"
info "Repository root: $REPO_ROOT"
info "Backup dir: $BACKUP_DIR"
info "Options: preserve-data=$KEEP_DATA remove-docker=$REMOVE_DOCKER dry-run=$DRY_RUN"

confirm_or_abort(){
  if [ "$NON_INTERACTIVE" = "yes" ]; then return 0; fi
  read -r -p "$1 [y/N]: " ANS
  case "$ANS" in [Yy]*) return 0;; *) err "Aborted by user";; esac
}

# Step 1 - stop systemd services if present
info "Stopping systemd services (if present)"
SYSTEMD_UNITS=(aiagent-app.service aiagent-rq.service aiagent.service)
for u in "${SYSTEMD_UNITS[@]}"; do
  if systemctl list-units --full -all | grep -q "^${u}"; then
    info "Stopping and disabling $u"
    run "systemctl stop $u || true"
    run "systemctl disable $u || true"
  fi
done
run "systemctl daemon-reload || true"

# Step 2 - backup repo and config
info "Creating backups (repo + env + systemd units)"
run "mkdir -p \"$BACKUP_DIR\""
# Copy repository (best-effort, avoid copying huge docker images)
if [ -d "$REPO_ROOT" ]; then
  info "Archiving repository to backup"
  if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] tar -czf ${BACKUP_DIR}/repo_${TIMESTAMP}.tgz -C \"${REPO_ROOT}\" ."
  else
    tar -czf "${BACKUP_DIR}/repo_${TIMESTAMP}.tgz" -C "${REPO_ROOT}" . || warn "Tar of repo had non-fatal errors"
  fi
fi
# Copy /etc/ai-agent env if exists
if [ -d "$ENV_DIR" ]; then
  run "cp -a \"$ENV_DIR\" \"$BACKUP_DIR/\" || true"
fi
# Save list of systemd units
run "mkdir -p \"$BACKUP_DIR/systemd\" || true"
for u in "${SYSTEMD_UNITS[@]}"; do
  if [ -f \"$SYSTEMD_DIR/$u\" ]; then run "cp -a \"$SYSTEMD_DIR/$u\" \"$BACKUP_DIR/systemd/\" || true"; fi
done

info "Backups completed: $BACKUP_DIR"

# Step 3 - optionally stop and remove docker containers/images
if [ "$REMOVE_DOCKER" = "yes" ]; then
  if command -v docker >/dev/null 2>&1; then
    info "Stopping known containers"
    CONTAINERS=(aiagent_web aiagent_worker aiagent-redis aiagent-redis-1 aiagent-web aiagent-worker)
    for c in "${CONTAINERS[@]}"; do
      if docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
        info "Stopping container $c"
        run "docker rm -f \"$c\" || true"
      fi
    done
    # remove images by tag
    IMAGES=(aiagent_web:latest aiagent_worker:latest aiagent_web aiagent_worker)
    for img in "${IMAGES[@]}"; do
      if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${img}$"; then
        info "Removing docker image $img"
        run "docker rmi -f \"$img\" || true"
      fi
    done
  else
    warn "Docker not installed; skipping docker removal"
  fi
fi

# Step 4 - remove systemd unit files
info "Removing systemd unit files"
for u in "${SYSTEMD_UNITS[@]}"; do
  if [ -f "$SYSTEMD_DIR/$u" ]; then
    if [ "$NON_INTERACTIVE" != "yes" ]; then
      confirm_or_abort "Remove $SYSTEMD_DIR/$u?"
    fi
    run "rm -f \"$SYSTEMD_DIR/$u\" || true"
    info "Removed $SYSTEMD_DIR/$u"
  fi
done
run "systemctl daemon-reload || true"

# Step 5 - remove installed files in /opt paths and venv (ask unless preserve-data)
if [ "$KEEP_DATA" = "yes" ]; then
  info "Preserving application data as requested (--preserve-data). Skipping deletion of $TARGET_DIR and /var/log/aiagent"
else
  # Check both canonical and legacy paths
  if [ -d "$TARGET_DIR" ]; then
    if [ "$NON_INTERACTIVE" != "yes" ]; then
      confirm_or_abort "Delete installed target directory $TARGET_DIR and data under it?"
    fi
    info "Deleting $TARGET_DIR"
    run "rm -rf \"$TARGET_DIR\" || true"
  elif [ -d "$TARGET_DIR_LEGACY" ]; then
    if [ "$NON_INTERACTIVE" != "yes" ]; then
      confirm_or_abort "Delete legacy installation directory $TARGET_DIR_LEGACY and data under it?"
    fi
    info "Deleting legacy $TARGET_DIR_LEGACY"
    run "rm -rf \"$TARGET_DIR_LEGACY\" || true"
  else
    info "Neither $TARGET_DIR nor $TARGET_DIR_LEGACY present, skipping"
  fi

  # logs
  if [ -d "/var/log/aiagent" ]; then
    if [ "$NON_INTERACTIVE" != "yes" ]; then
      confirm_or_abort "Delete logs under /var/log/aiagent?"
    fi
    run "rm -rf /var/log/aiagent || true"
  fi

  # env dir
  if [ -d "$ENV_DIR" ]; then
    if [ "$NON_INTERACTIVE" != "yes" ]; then
      confirm_or_abort "Delete configuration at $ENV_DIR?"
    fi
    run "rm -rf \"$ENV_DIR\" || true"
  fi
fi

# Step 6 - remove user if desired (only if system user exists and not in use)
if id -u "$AI_USER" >/dev/null 2>&1; then
  if [ "$NON_INTERACTIVE" != "yes" ]; then
    confirm_or_abort "Remove system user $AI_USER (home: /home/$AI_USER) ?"
  fi
  info "Deleting user $AI_USER"
  run "userdel --remove \"$AI_USER\" || true"
fi

info "Uninstall steps completed. Backups kept at: $BACKUP_DIR"

# Final message
info "Uninstall finished. Inspect logs: $LOGFILE"
info "If you intentionally preserved data, manual cleanup may still be required for DBs or external services."
exit 0

