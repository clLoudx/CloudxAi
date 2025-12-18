#!/usr/bin/env bash
#
# .cursor/agents/refactor.sh — AI Refactoring Agent
#
# Refactors code safely following max-logic principles
# Usage: ./agents/refactor.sh [file] [pattern]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_FILE="${1:-}"
PATTERN="${2:-}"

info(){ echo "[REFACTOR] $*"; }
warn(){ echo "[REFACTOR] WARN: $*" >&2; }
err(){ echo "[REFACTOR] ERROR: $*" >&2; exit 1; }

if [ -z "$TARGET_FILE" ]; then
    err "Usage: $0 <file> [pattern]"
fi

if [ ! -f "$TARGET_FILE" ]; then
    err "File not found: $TARGET_FILE"
fi

info "Refactoring: $TARGET_FILE"

# Create backup before refactoring
BACKUP_DIR="/opt/ai-agent-backups"
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/$(basename "$TARGET_FILE").refactor.$(date +%Y%m%d_%H%M%S)"
cp "$TARGET_FILE" "$BACKUP"
info "Backup created: $BACKUP"

# Common refactoring patterns
if [ -z "$PATTERN" ] || [ "$PATTERN" = "paths" ]; then
    # Refactor paths
    if grep -q "/opt/aiagent[^-/]" "$TARGET_FILE" 2>/dev/null; then
        info "Refactoring path references..."
        sed -i 's|/opt/aiagent\([^-/]\)|/opt/ai-agent\1|g' "$TARGET_FILE"
        info "Path references updated"
    fi
fi

if [ -z "$PATTERN" ] || [ "$PATTERN" = "charts" ]; then
    # Refactor chart references
    if grep -q "charts/aiagent" "$TARGET_FILE" 2>/dev/null; then
        info "Refactoring chart references..."
        sed -i 's|charts/aiagent|devops/helm/aiagent|g' "$TARGET_FILE"
        info "Chart references updated"
    fi
fi

if [ -z "$PATTERN" ] || [ "$PATTERN" = "modules" ]; then
    # Refactor module sources
    if grep -q "ai-agent/modules/healthcheck.sh" "$TARGET_FILE" 2>/dev/null; then
        info "Refactoring healthcheck module reference..."
        sed -i 's|ai-agent/modules/healthcheck.sh|devops/tools/healthcheck.sh|g' "$TARGET_FILE"
        info "Module reference updated"
    fi
fi

# Validate after refactoring
if [[ "$TARGET_FILE" == *.sh ]]; then
    if bash -n "$TARGET_FILE" 2>/dev/null; then
        info "Bash syntax validation passed"
    else
        warn "Bash syntax validation failed - restoring backup"
        cp "$BACKUP" "$TARGET_FILE"
        exit 1
    fi
fi

info "Refactoring complete. Backup: $BACKUP"

exit 0

