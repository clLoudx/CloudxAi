#!/usr/bin/env bash
#
# .cursor/agents/debugger.sh — AI Debugger Agent
#
# Analyzes logs, identifies issues, suggests fixes
# Usage: ./agents/debugger.sh [component] [log_file]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENT="${1:-all}"
LOG_FILE="${2:-}"

info(){ echo "[DEBUGGER] $*"; }
warn(){ echo "[DEBUGGER] WARN: $*" >&2; }

debug_component() {
    local comp="$1"
    info "Debugging component: $comp"
    
    case "$comp" in
        installer)
            info "Checking installer logs..."
            if [ -f "/var/log/aiagent_local_installer.log" ]; then
                tail -50 "/var/log/aiagent_local_installer.log" | grep -i "error\|fail" || info "No errors in installer log"
            fi
            ;;
        service)
            info "Checking service status..."
            systemctl status aiagent.service --no-pager -l || warn "Service not found or not running"
            ;;
        health)
            info "Checking health endpoint..."
            curl -sS http://127.0.0.1:8000/healthz || warn "Health endpoint not responding"
            ;;
        python)
            info "Checking Python imports..."
            if [ -d "/opt/ai-agent/venv" ]; then
                /opt/ai-agent/venv/bin/python -c "import flask, redis, rq, requests; print('OK')" || warn "Python imports failed"
            fi
            ;;
        all)
            debug_component installer
            debug_component service
            debug_component health
            debug_component python
            ;;
        *)
            warn "Unknown component: $comp"
            ;;
    esac
}

if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    info "Analyzing log file: $LOG_FILE"
    grep -i "error\|fail\|exception" "$LOG_FILE" | tail -20 || info "No errors found in log"
fi

debug_component "$COMPONENT"

info "Debugger analysis complete"

exit 0

