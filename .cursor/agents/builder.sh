#!/usr/bin/env bash
#
# .cursor/agents/builder.sh — AI Builder Agent
#
# Analyzes code, suggests fixes, applies safe changes
# Usage: ./agents/builder.sh [file] [--apply]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_FILE="${1:-}"
APPLY="${2:-}"

info(){ echo "[BUILDER] $*"; }
warn(){ echo "[BUILDER] WARN: $*" >&2; }
err(){ echo "[BUILDER] ERROR: $*" >&2; exit 1; }

if [ -z "$TARGET_FILE" ]; then
    err "Usage: $0 <file> [--apply]"
fi

if [ ! -f "$TARGET_FILE" ]; then
    err "File not found: $TARGET_FILE"
fi

info "Analyzing: $TARGET_FILE"

# Check for common issues
ISSUES=()

# Check for old path references
if grep -q "/opt/aiagent[^-/]" "$TARGET_FILE" 2>/dev/null; then
    ISSUES+=("Old path reference: /opt/aiagent (should be /opt/ai-agent)")
fi

# Check for old chart references
if grep -q "charts/aiagent" "$TARGET_FILE" 2>/dev/null; then
    ISSUES+=("Old chart reference: charts/aiagent (should be devops/helm/aiagent)")
fi

# Check for bash syntax errors
if [[ "$TARGET_FILE" == *.sh ]]; then
    if ! bash -n "$TARGET_FILE" 2>/dev/null; then
        ISSUES+=("Bash syntax errors detected")
    fi
fi

# Check for Python syntax errors
if [[ "$TARGET_FILE" == *.py ]]; then
    if ! python3 -m py_compile "$TARGET_FILE" 2>/dev/null; then
        ISSUES+=("Python syntax errors detected")
    fi
fi

# Report issues
if [ ${#ISSUES[@]} -eq 0 ]; then
    info "No issues found in $TARGET_FILE"
    exit 0
fi

warn "Found ${#ISSUES[@]} issue(s):"
for issue in "${ISSUES[@]}"; do
    warn "  - $issue"
done

# Apply fixes if requested
if [ "$APPLY" = "--apply" ]; then
    info "Applying fixes..."
    
    # Fix path references
    if grep -q "/opt/aiagent[^-/]" "$TARGET_FILE" 2>/dev/null; then
        sed -i 's|/opt/aiagent\([^-/]\)|/opt/ai-agent\1|g' "$TARGET_FILE"
        info "Fixed path references"
    fi
    
    # Fix chart references
    if grep -q "charts/aiagent" "$TARGET_FILE" 2>/dev/null; then
        sed -i 's|charts/aiagent|devops/helm/aiagent|g' "$TARGET_FILE"
        info "Fixed chart references"
    fi
    
    info "Fixes applied. Review changes before committing."
else
    info "Run with --apply to automatically fix issues"
fi

exit 0

