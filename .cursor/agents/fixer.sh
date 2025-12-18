#!/usr/bin/env bash
#
# .cursor/agents/fixer.sh — AI Fixer Agent
#
# Takes error output, fixes code automatically
# Usage: ./agents/fixer.sh [file] [error_message]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_FILE="${1:-}"
ERROR_MSG="${2:-}"

info(){ echo "[FIXER] $*"; }
warn(){ echo "[FIXER] WARN: $*" >&2; }
err(){ echo "[FIXER] ERROR: $*" >&2; exit 1; }

if [ -z "$TARGET_FILE" ]; then
    err "Usage: $0 <file> [error_message]"
fi

if [ ! -f "$TARGET_FILE" ]; then
    err "File not found: $TARGET_FILE"
fi

info "Fixing: $TARGET_FILE"

# Common fix patterns
if echo "$ERROR_MSG" | grep -q "No such file or directory"; then
    # Missing file - check if it's a path issue
    missing_path=$(echo "$ERROR_MSG" | grep -oE "/[^ ]+" | head -1)
    if [[ "$missing_path" == *"/opt/aiagent"* ]]; then
        warn "Detected old path in error: $missing_path"
        info "Suggestion: Update to /opt/ai-agent"
    fi
fi

if echo "$ERROR_MSG" | grep -q "ModuleNotFoundError\|ImportError"; then
    # Python import error
    missing_module=$(echo "$ERROR_MSG" | grep -oE "No module named '[^']+'" | sed "s/No module named '//;s/'//")
    warn "Missing Python module: $missing_module"
    info "Suggestion: Add to requirements.txt or install: pip install $missing_module"
fi

if echo "$ERROR_MSG" | grep -q "chart.*not found\|Chart.*missing"; then
    # Helm chart error
    warn "Helm chart issue detected"
    info "Suggestion: Verify chart exists at devops/helm/aiagent/"
fi

if echo "$ERROR_MSG" | grep -q "service.*not found\|Service.*missing"; then
    # Systemd service error
    warn "Systemd service issue detected"
    info "Suggestion: Verify service file exists at devops/systemd/aiagent.service"
fi

# Run builder agent for comprehensive analysis
if [ -f "$REPO_ROOT/.cursor/agents/builder.sh" ]; then
    info "Running builder agent for comprehensive analysis..."
    bash "$REPO_ROOT/.cursor/agents/builder.sh" "$TARGET_FILE" --apply || true
fi

info "Fixer analysis complete. Review suggestions above."

exit 0

