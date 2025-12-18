#!/usr/bin/env bash
#
# devops/smoke_tests/verify_unification.sh
# Static verification script for canonical unification
#
# Verifies:
# - No remaining /opt/aiagent references (excluding docs, migration vars, agent patterns)
# - No remaining charts/aiagent references (excluding docs)
# - Presence of devops/helm/aiagent/Chart.yaml
# - devops/tools/healthcheck.sh contains post_deploy_smoke function
# - devops/systemd/aiagent.service exists and contains User=aiagent
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0
WARNINGS=0

info(){ echo "[INFO] $*"; }
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; WARNINGS=$((WARNINGS+1)); }
err(){ echo "[ERROR] $*"; ERRORS=$((ERRORS+1)); }

info "Starting unification verification..."

# Check 1: No remaining /opt/aiagent references
info "Check 1: Path consistency (/opt/aiagent -> /opt/ai-agent)"
count=$(grep -r "/opt/aiagent[^-/]" --include="*.sh" --include="*.service" "$REPO_ROOT" 2>/dev/null | \
  grep -v ".deprecated" | \
  grep -v "docs/" | \
  grep -v "TARGET_DIR_LEGACY" | \
  grep -v ".cursor/agents" | \
  grep -v "verify_unification.sh" | \
  wc -l)
if [ "$count" -eq 0 ]; then
  ok "No /opt/aiagent references found (excluding docs, migration vars, agent patterns)"
else
  err "Found $count /opt/aiagent references"
  grep -r "/opt/aiagent[^-/]" --include="*.sh" --include="*.service" "$REPO_ROOT" 2>/dev/null | \
    grep -v ".deprecated" | \
    grep -v "docs/" | \
    grep -v "TARGET_DIR_LEGACY" | \
    grep -v ".cursor/agents" | \
    head -10
fi

# Check 2: No remaining charts/aiagent references
info "Check 2: Chart consistency (charts/aiagent -> devops/helm/aiagent)"
count=$(grep -r "charts/aiagent" --include="*.sh" --include="*.yml" --include="*.yaml" "$REPO_ROOT" 2>/dev/null | \
  grep -v ".deprecated" | \
  grep -v "docs/" | \
  grep -v ".cursor/agents" | \
  grep -v "verify_unification.sh" | \
  wc -l)
if [ "$count" -eq 0 ]; then
  ok "No charts/aiagent references found (excluding docs, agent patterns)"
else
  err "Found $count charts/aiagent references"
  grep -r "charts/aiagent" --include="*.sh" --include="*.yml" --include="*.yaml" "$REPO_ROOT" 2>/dev/null | \
    grep -v ".deprecated" | \
    grep -v "docs/" | \
    grep -v ".cursor/agents" | \
    head -10
fi

# Check 3: Chart.yaml exists
info "Check 3: Canonical Helm chart exists"
if [ -f "$REPO_ROOT/devops/helm/aiagent/Chart.yaml" ]; then
  ok "devops/helm/aiagent/Chart.yaml exists"
else
  err "devops/helm/aiagent/Chart.yaml missing"
fi

# Check 4: healthcheck.sh contains post_deploy_smoke
info "Check 4: Healthcheck module contains post_deploy_smoke function"
if [ -f "$REPO_ROOT/devops/tools/healthcheck.sh" ]; then
  if grep -q "post_deploy_smoke" "$REPO_ROOT/devops/tools/healthcheck.sh"; then
    ok "devops/tools/healthcheck.sh contains post_deploy_smoke function"
  else
    err "devops/tools/healthcheck.sh missing post_deploy_smoke function"
  fi
else
  err "devops/tools/healthcheck.sh missing"
fi

# Check 5: systemd service exists and has correct user
info "Check 5: Systemd service exists with User=aiagent"
if [ -f "$REPO_ROOT/devops/systemd/aiagent.service" ]; then
  if grep -q "User=aiagent" "$REPO_ROOT/devops/systemd/aiagent.service"; then
    ok "devops/systemd/aiagent.service exists and contains User=aiagent"
  else
    err "devops/systemd/aiagent.service missing User=aiagent"
  fi
  if grep -q "WorkingDirectory=/opt/ai-agent" "$REPO_ROOT/devops/systemd/aiagent.service"; then
    ok "devops/systemd/aiagent.service has correct WorkingDirectory"
  else
    err "devops/systemd/aiagent.service missing or incorrect WorkingDirectory"
  fi
else
  err "devops/systemd/aiagent.service missing"
fi

# Summary
echo ""
info "Verification complete"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"

if [ $ERRORS -eq 0 ]; then
  ok "All checks passed"
  exit 0
else
  err "Verification failed with $ERRORS error(s)"
  exit 1
fi

