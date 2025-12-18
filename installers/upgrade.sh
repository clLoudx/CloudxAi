#!/usr/bin/env bash
#
# installers/upgrade.sh — Safe upgrade script for AI-Agent
#
# Responsibilities:
#   - Detect current installation path
#   - Backup existing installation
#   - Run installer_master.sh with upgrade flag
#   - Verify health after upgrade
#   - Rollback on failure
#
# Usage:
#   sudo ./installers/upgrade.sh [--backup-dir PATH] [--no-rollback] [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/aiagent_upgrade_${TIMESTAMP}}"
NO_ROLLBACK="no"
DRY_RUN="no"
NON_INTERACTIVE="no"

# Support both paths for migration
TARGET_DIR_CANONICAL="/opt/ai-agent"
TARGET_DIR_LEGACY="/opt/aiagent"
TARGET_DIR=""

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
        --no-rollback) NO_ROLLBACK="yes"; shift;;
        --dry-run) DRY_RUN="yes"; shift;;
        --non-interactive) NON_INTERACTIVE="yes"; shift;;
        -h|--help)
            echo "Usage: $0 [--backup-dir PATH] [--no-rollback] [--dry-run] [--non-interactive]"
            exit 0;;
        *) warn "Unknown option: $1"; shift;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    err "upgrade.sh must run as root"
    exit 1
fi

title "AI-Agent Upgrade Script"

###########################################################
# Detect current installation
###########################################################
info "Detecting current installation..."
if [ -d "$TARGET_DIR_CANONICAL" ]; then
    TARGET_DIR="$TARGET_DIR_CANONICAL"
    ok "Found installation at $TARGET_DIR (canonical)"
elif [ -d "$TARGET_DIR_LEGACY" ]; then
    TARGET_DIR="$TARGET_DIR_LEGACY"
    warn "Found installation at $TARGET_DIR (legacy - will migrate to canonical path)"
else
    err "No installation found at $TARGET_DIR_CANONICAL or $TARGET_DIR_LEGACY"
    exit 1
fi

###########################################################
# Create backup
###########################################################
title "Creating backup"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would backup $TARGET_DIR to $BACKUP_DIR"
else
    mkdir -p "$BACKUP_DIR"
    
    # Backup installation directory
    if [ -d "$TARGET_DIR" ]; then
        info "Backing up $TARGET_DIR..."
        tar -czf "$BACKUP_DIR/installation_${TIMESTAMP}.tar.gz" -C "$(dirname "$TARGET_DIR")" "$(basename "$TARGET_DIR")" || {
            err "Backup failed"
            exit 1
        }
        ok "Installation backed up"
    fi
    
    # Backup systemd services
    mkdir -p "$BACKUP_DIR/systemd"
    for svc in aiagent.service ai-agent.service; do
        if [ -f "/etc/systemd/system/$svc" ]; then
            cp "/etc/systemd/system/$svc" "$BACKUP_DIR/systemd/" || true
        fi
    done
    
    # Backup configuration
    if [ -d "/etc/ai-agent" ]; then
        cp -a /etc/ai-agent "$BACKUP_DIR/" || true
    fi
    
    ok "Backup complete: $BACKUP_DIR"
fi

###########################################################
# Run upgrade
###########################################################
title "Running upgrade"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would run: installer_master.sh --non-interactive"
else
    if [ -f "$REPO_ROOT/installer_master.sh" ] && [ -x "$REPO_ROOT/installer_master.sh" ]; then
        info "Executing installer_master.sh..."
        if bash "$REPO_ROOT/installer_master.sh" --non-interactive; then
            ok "Upgrade installation completed"
        else
            err "Upgrade installation failed"
            if [ "$NO_ROLLBACK" != "yes" ]; then
                warn "Initiating rollback..."
                if [ -f "$REPO_ROOT/installers/rollback.sh" ]; then
                    bash "$REPO_ROOT/installers/rollback.sh" --backup-dir "$BACKUP_DIR" --non-interactive || true
                fi
            fi
            exit 1
        fi
    else
        err "installer_master.sh not found"
        exit 1
    fi
fi

###########################################################
# Verify health after upgrade
###########################################################
title "Verifying health after upgrade"
if [ "$DRY_RUN" = "yes" ]; then
    info "[DRY-RUN] Would run health checks"
else
    sleep 5  # Give services time to start
    
    # Check systemd service if in local mode
    if systemctl list-units --full -all | grep -q "aiagent.service"; then
        if systemctl is-active --quiet aiagent.service; then
            ok "Service is active"
        else
            warn "Service is not active - checking status"
            systemctl status aiagent.service || true
        fi
    fi
    
    # Run healthcheck
    if command -v post_deploy_smoke >/dev/null 2>&1; then
        info "Running smoke tests..."
        post_deploy_smoke local aiagent-web /healthz 8000 60 || {
            warn "Smoke tests reported issues"
            if [ "$NO_ROLLBACK" != "yes" ]; then
                warn "Initiating rollback due to health check failure..."
                if [ -f "$REPO_ROOT/installers/rollback.sh" ]; then
                    bash "$REPO_ROOT/installers/rollback.sh" --backup-dir "$BACKUP_DIR" --non-interactive || true
                fi
                exit 1
            fi
        }
    else
        warn "post_deploy_smoke not available - skipping health check"
    fi
fi

###########################################################
# Wrap-up
###########################################################
ok "Upgrade complete"
info "Backup location: $BACKUP_DIR"
info "Installation directory: $TARGET_DIR_CANONICAL"

exit 0

