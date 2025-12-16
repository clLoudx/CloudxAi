#!/usr/bin/env bash
#
# devops/tools/production_checks.sh — Production Readiness Checks
#
# Responsibilities:
#   - Verify all dependencies
#   - Check disk space
#   - Verify network connectivity
#   - Validate Kubernetes cluster (if kube mode)
#   - Check security settings
#   - Resource limits validation
#
# Usage:
#   ./devops/tools/production_checks.sh [--mode local|kube] [--strict]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${MODE:-local}"
STRICT="${STRICT:-no}"
EXIT_CODE=0

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

###########################################################
# Parse arguments
###########################################################
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2;;
        --strict) STRICT="yes"; shift;;
        -h|--help)
            echo "Usage: $0 [--mode local|kube] [--strict]"
            exit 0;;
        *) warn "Unknown option: $1"; shift;;
    esac
done

title "Production Readiness Checks"

###########################################################
# Check system dependencies
###########################################################
check_dependencies() {
    title "Checking system dependencies"
    local missing=()
    
    # Required for all modes
    local required=(python3 curl wget git)
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    # Mode-specific requirements
    if [ "$MODE" = "kube" ]; then
        for cmd in kubectl helm; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                missing+=("$cmd")
            fi
        done
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        EXIT_CODE=1
    else
        ok "All dependencies present"
    fi
}

###########################################################
# Check disk space
###########################################################
check_disk_space() {
    title "Checking disk space"
    local min_gb=2
    local avail_kb
    avail_kb=$(df --output=avail / | tail -n1 | tr -d ' ' || echo "0")
    local avail_gb=$((avail_kb / 1024 / 1024))
    
    if [ "$avail_gb" -lt "$min_gb" ]; then
        err "Low disk space: ${avail_gb}GB available (minimum: ${min_gb}GB)"
        EXIT_CODE=1
    else
        ok "Disk space OK: ${avail_gb}GB available"
    fi
}

###########################################################
# Check network connectivity
###########################################################
check_network() {
    title "Checking network connectivity"
    
    # Check DNS
    if ! getent hosts google.com >/dev/null 2>&1; then
        warn "DNS resolution may be failing"
        if [ "$STRICT" = "yes" ]; then
            EXIT_CODE=1
        fi
    else
        ok "DNS resolution OK"
    fi
    
    # Check internet connectivity
    if ! curl -sS --max-time 5 https://www.google.com >/dev/null 2>&1; then
        warn "Internet connectivity check failed"
        if [ "$STRICT" = "yes" ]; then
            EXIT_CODE=1
        fi
    else
        ok "Internet connectivity OK"
    fi
}

###########################################################
# Check Python environment
###########################################################
check_python() {
    title "Checking Python environment"
    
    if ! command -v python3 >/dev/null 2>&1; then
        err "python3 not found"
        EXIT_CODE=1
        return
    fi
    
    local py_version
    py_version=$(python3 --version 2>&1 | awk '{print $2}')
    ok "Python version: $py_version"
    
    # Check if venv exists and is valid
    local venv_path="/opt/ai-agent/venv"
    if [ -d "$venv_path" ]; then
        if [ -x "$venv_path/bin/python" ]; then
            ok "Virtual environment found at $venv_path"
        else
            warn "Virtual environment at $venv_path is invalid"
            if [ "$STRICT" = "yes" ]; then
                EXIT_CODE=1
            fi
        fi
    else
        warn "Virtual environment not found (will be created during install)"
    fi
}

###########################################################
# Check Kubernetes cluster (kube mode only)
###########################################################
check_kubernetes() {
    if [ "$MODE" != "kube" ]; then
        return
    fi
    
    title "Checking Kubernetes cluster"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        err "kubectl not found"
        EXIT_CODE=1
        return
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        err "Cannot connect to Kubernetes cluster"
        EXIT_CODE=1
        return
    fi
    
    ok "Kubernetes cluster accessible"
    
    # Check Helm
    if ! command -v helm >/dev/null 2>&1; then
        err "helm not found"
        EXIT_CODE=1
        return
    fi
    
    ok "Helm available"
    
    # Check required namespaces
    local required_ns=(cert-manager ingress-nginx)
    for ns in "${required_ns[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            ok "Namespace $ns exists"
        else
            warn "Namespace $ns not found (will be created during install)"
        fi
    done
}

###########################################################
# Check security settings
###########################################################
check_security() {
    title "Checking security settings"
    
    # Check if running as root (for installers)
    if [ "$(id -u)" -eq 0 ]; then
        warn "Running as root (expected for installers)"
    fi
    
    # Check file permissions on sensitive files
    local sensitive_files=("/etc/ai-agent/env")
    for f in "${sensitive_files[@]}"; do
        if [ -f "$f" ]; then
            local perms
            perms=$(stat -c "%a" "$f" 2>/dev/null || echo "000")
            if [ "$perms" != "600" ] && [ "$perms" != "640" ]; then
                warn "File $f has insecure permissions: $perms (should be 600 or 640)"
                if [ "$STRICT" = "yes" ]; then
                    EXIT_CODE=1
                fi
            else
                ok "File $f has secure permissions: $perms"
            fi
        fi
    done
}

###########################################################
# Check resource limits
###########################################################
check_resources() {
    title "Checking resource limits"
    
    # Check memory
    local mem_total_kb
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}' || echo "0")
    local mem_gb=$((mem_total_kb / 1024 / 1024))
    
    if [ "$mem_gb" -lt 2 ]; then
        warn "Low memory: ${mem_gb}GB (recommended: 4GB+)"
        if [ "$STRICT" = "yes" ]; then
            EXIT_CODE=1
        fi
    else
        ok "Memory: ${mem_gb}GB"
    fi
    
    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "1")
    if [ "$cpu_cores" -lt 2 ]; then
        warn "Low CPU cores: $cpu_cores (recommended: 2+)"
    else
        ok "CPU cores: $cpu_cores"
    fi
}

###########################################################
# Main execution
###########################################################
main() {
    check_dependencies
    check_disk_space
    check_network
    check_python
    check_kubernetes
    check_security
    check_resources
    
    if [ $EXIT_CODE -eq 0 ]; then
        ok "All production checks passed"
    else
        err "Some production checks failed"
        if [ "$STRICT" = "yes" ]; then
            exit 1
        fi
    fi
    
    exit $EXIT_CODE
}

main

