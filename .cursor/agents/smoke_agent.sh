#!/usr/bin/env bash
#
# .cursor/agents/smoke_agent.sh — AI Smoke Test Agent
#
# Runs appropriate smoke tests for deployment mode
# Usage: ./agents/smoke_agent.sh [mode]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-auto}"

info(){ echo "[SMOKE] $*"; }
warn(){ echo "[SMOKE] WARN: $*" >&2; }

# Auto-detect mode
if [ "$MODE" = "auto" ]; then
    if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
        MODE="kube"
    elif systemctl list-units --full -all | grep -q "aiagent.service"; then
        MODE="local"
    else
        MODE="local"  # default
    fi
    info "Auto-detected mode: $MODE"
fi

case "$MODE" in
    local)
        info "Running local smoke tests..."
        if [ -f "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" ]; then
            bash "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" local aiagent-web /healthz 8000 60
        else
            warn "post_deploy_smoke.sh not found"
        fi
        
        # Check service
        if systemctl is-active --quiet aiagent.service; then
            info "✓ Service is active"
        else
            warn "✗ Service is not active"
        fi
        ;;
    kube)
        info "Running Kubernetes smoke tests..."
        NAMESPACE="${NAMESPACE:-aiagent}"
        if [ -f "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" ]; then
            bash "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" "$NAMESPACE" aiagent-web /healthz 8000 120
        else
            warn "post_deploy_smoke.sh not found"
        fi
        
        # Check pods
        if command -v kubectl >/dev/null 2>&1; then
            if kubectl -n "$NAMESPACE" get pods 2>/dev/null | grep -q Running; then
                info "✓ Pods are running"
            else
                warn "✗ No running pods found"
            fi
        fi
        ;;
    docker)
        info "Running Docker smoke tests..."
        if [ -f "$REPO_ROOT/devops/smoke_tests/docker_compose_check.sh" ]; then
            bash "$REPO_ROOT/devops/smoke_tests/docker_compose_check.sh"
        else
            warn "docker_compose_check.sh not found"
        fi
        ;;
    *)
        err "Unknown mode: $MODE (use: local, kube, docker, or auto)"
        ;;
esac

info "Smoke test agent complete"

exit 0

