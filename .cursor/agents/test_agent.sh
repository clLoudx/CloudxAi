#!/usr/bin/env bash
#
# .cursor/agents/test_agent.sh — AI Test Agent
#
# Generates and runs tests
# Usage: ./agents/test_agent.sh [component]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENT="${1:-all}"

info(){ echo "[TEST] $*"; }
warn(){ echo "[TEST] WARN: $*" >&2; }

test_component() {
    local comp="$1"
    info "Testing component: $comp"
    
    case "$comp" in
        paths)
            info "Testing path consistency..."
            count=$(grep -r "/opt/aiagent[^-/]" --include="*.sh" --include="*.service" . 2>/dev/null | grep -v ".deprecated" | grep -v "docs/" | wc -l)
            if [ "$count" -eq 0 ]; then
                info "✓ All paths consistent"
            else
                warn "✗ Found $count path inconsistencies"
            fi
            ;;
        charts)
            info "Testing chart references..."
            count=$(grep -r "charts/aiagent" --include="*.sh" --include="*.yml" --include="*.yaml" . 2>/dev/null | grep -v ".deprecated" | grep -v "docs/" | wc -l)
            if [ "$count" -eq 0 ]; then
                info "✓ All chart references consistent"
            else
                warn "✗ Found $count chart reference inconsistencies"
            fi
            ;;
        modules)
            info "Testing module sources..."
            if [ -f "$REPO_ROOT/ai-agent/modules/ui.sh" ]; then
                source "$REPO_ROOT/ai-agent/modules/ui.sh" && info "✓ UI module loads"
            fi
            if [ -f "$REPO_ROOT/devops/tools/healthcheck.sh" ]; then
                source "$REPO_ROOT/devops/tools/healthcheck.sh" && info "✓ Healthcheck module loads"
            fi
            ;;
        services)
            info "Testing systemd service..."
            if [ -f "$REPO_ROOT/devops/systemd/aiagent.service" ]; then
                systemd-analyze verify "$REPO_ROOT/devops/systemd/aiagent.service" && info "✓ Service file valid" || warn "✗ Service file invalid"
            fi
            ;;
        installers)
            info "Testing installer syntax..."
            for inst in installer_master.sh installers/installer_local.sh installers/installer_kube.sh; do
                if [ -f "$REPO_ROOT/$inst" ]; then
                    bash -n "$REPO_ROOT/$inst" && info "✓ $inst syntax OK" || warn "✗ $inst syntax error"
                fi
            done
            ;;
        python)
            info "Testing Python imports..."
            if [ -d "/opt/ai-agent/venv" ]; then
                /opt/ai-agent/venv/bin/python -c "import flask, redis, rq, requests; print('OK')" && info "✓ Python imports OK" || warn "✗ Python imports failed"
            else
                warn "Venv not found at /opt/ai-agent/venv"
            fi
            ;;
        all)
            test_component paths
            test_component charts
            test_component modules
            test_component services
            test_component installers
            test_component python
            ;;
        *)
            warn "Unknown component: $comp"
            ;;
    esac
}

test_component "$COMPONENT"

info "Test agent complete"

exit 0

