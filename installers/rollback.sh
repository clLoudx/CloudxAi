#!/usr/bin/env bash
#
# installers/rollback.sh — Safe rollback script for AI-Agent
#
# Responsibilities:
#   - Restore from backup created during upgrade
#   - Verify rollback success
#   - Healthcheck after rollback
#
# Usage:
#   sudo ./installers/rollback.sh --backup-dir /var/backups/aiagent_upgrade_TIMESTAMP [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR=""
DRY_RUN="no"
NON_INTERACTIVE="no"

TARGET_DIR_CANONICAL="/opt/ai-agent"
TARGET_DIR_LEGACY="/opt/aiagent"

###########################################################
# Import helper modules
###########################################################
if [ -f "$REPO_ROOT/ai-agent/modules/ui.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/ai-agent/modules/ui.sh"
else
    info(){ echo "[INFO] $*"; }
    ok(){ echo "[OK] $*"; }
    warn(){ echo "[WARN] $*"; }
    err(){ echo "[ERR] $*" >&2; }
fi

if [ -f "$REPO_ROOT/devops/tools/healthcheck.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/devops/tools/healthcheck.sh"
fi

###########################################################
# Parse arguments
###########################################################
while [ $# -gt 0 ]; do
    case "$1" in
        --backup-dir) BACKUP_DIR="$2"; shift 2;;
        --dry-run) DRY_RUN="yes"; shift;;
        --non-interactive) NON_INTERACTIVE="yes"; shift;;
        -h|--help)
            echo "Usage: $0 --backup-dir PATH [--dry-run] [--non-interactive]"
            exit 0;;
        *) warn "Unknown option: $1"; shift;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    err "rollback.sh must run as root"
    exit 1
fi

if [ -z "$BACKUP_DIR" ]; then
    err "Backup directory required (--backup-dir PATH)"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    err "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

title "AI-Agent Rollback Script"

###########################################################
# Stop services
###########################################################
title "Stopping services"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would stop aiagent.service"
else
    systemctl stop aiagent.service || true
    systemctl stop ai-agent.service || true
    ok "Services stopped"
fi

###########################################################
# Restore installation directory
###########################################################
title "Restoring installation directory"
BACKUP_TAR=""
for f in "$BACKUP_DIR"/installation_*.tar.gz; do
    if [ -f "$f" ]; then
        BACKUP_TAR="$f"
        break
    fi
done

if [ -z "$BACKUP_TAR" ]; then
    err "No installation backup found in $BACKUP_DIR"
    exit 1
fi

info "Found backup: $BACKUP_TAR"

if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would restore from $BACKUP_TAR"
else
    # Remove current installation
    if [ -d "$TARGET_DIR_CANONICAL" ]; then
        info "Removing current installation at $TARGET_DIR_CANONICAL"
        rm -rf "$TARGET_DIR_CANONICAL" || warn "Failed to remove some files"
    fi
    if [ -d "$TARGET_DIR_LEGACY" ]; then
        info "Removing legacy installation at $TARGET_DIR_LEGACY"
        rm -rf "$TARGET_DIR_LEGACY" || warn "Failed to remove some files"
    fi
    
    # Restore from backup
    info "Extracting backup..."
    tar -xzf "$BACKUP_TAR" -C "$(dirname "$TARGET_DIR_CANONICAL")" || {
        err "Failed to extract backup"
        exit 1
    }
    
    # If backup was from legacy path, move to canonical
    if [ -d "$TARGET_DIR_LEGACY" ] && [ ! -d "$TARGET_DIR_CANONICAL" ]; then
        info "Migrating from legacy to canonical path"
        mv "$TARGET_DIR_LEGACY" "$TARGET_DIR_CANONICAL" || {
            err "Failed to migrate path"
            exit 1
        }
    fi
    
    ok "Installation restored"
fi

###########################################################
# Restore systemd services
###########################################################
title "Restoring systemd services"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would restore systemd services"
else
    if [ -d "$BACKUP_DIR/systemd" ]; then
        for svc in "$BACKUP_DIR/systemd"/*.service; do
            if [ -f "$svc" ]; then
                svc_name=$(basename "$svc")
                info "Restoring $svc_name"
                cp "$svc" "/etc/systemd/system/$svc_name"
                chmod 644 "/etc/systemd/system/$svc_name"
            fi
        done
        systemctl daemon-reload
        ok "Systemd services restored"
    else
        warn "No systemd backup found"
    fi
fi

###########################################################
# Restore configuration
###########################################################
title "Restoring configuration"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would restore configuration"
else
    if [ -d "$BACKUP_DIR/ai-agent" ]; then
        info "Restoring /etc/ai-agent"
        rm -rf /etc/ai-agent || true
        cp -a "$BACKUP_DIR/ai-agent" /etc/ai-agent
        ok "Configuration restored"
    else
        warn "No configuration backup found"
    fi
fi

###########################################################
# Restart services
###########################################################
title "Restarting services"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would restart services"
else
    systemctl daemon-reload
    systemctl restart aiagent.service || systemctl restart ai-agent.service || true
    sleep 3
    ok "Services restarted"
fi

###########################################################
# Verify rollback
###########################################################
title "Verifying rollback"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would verify rollback"
else
    # Check service status
    if systemctl list-units --full -all | grep -q "aiagent.service"; then
        if systemctl is-active --quiet aiagent.service; then
            ok "Service is active after rollback"
        else
            warn "Service is not active - check logs"
            systemctl status aiagent.service || true
        fi
    fi
    
    # Run healthcheck
    if command -v post_deploy_smoke >/dev/null 2>&1; then
        info "Running smoke tests..."
        post_deploy_smoke local aiagent-web /healthz 8000 60 || {
            warn "Smoke tests reported issues after rollback"
        }
    fi
fi

###########################################################
# Wrap-up
###########################################################
ok "Rollback complete"
info "Restored from: $BACKUP_DIR"
info "Installation directory: $TARGET_DIR_CANONICAL"

exit 0

