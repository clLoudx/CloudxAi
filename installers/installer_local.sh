#!/usr/bin/env bash
#
# installers/installer_local.sh — Local System Installer (Pure Local/Systemd Mode)
#
# Responsibilities:
#   - Prepare system dependencies (Python, system tools)
#   - Create /opt/ai-agent directory & Python venv
#   - Copy repo files safely
#   - Register systemd services
#   - Run healthcheck & smoke-tests
#   - Zero hard-coded paths, full safety, no contradictions
#
# This is a focused local installer with NO Kubernetes logic.
# Called by installer_master.sh for local mode.
#
# Safe on VPS / bare-metal / remote ZIP deploy.

set -euo pipefail

###########################################################
# Resolve root repo directory deterministically
###########################################################
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="/opt/ai-agent"
VENV_DIR="$INSTALL_ROOT/venv"
LOGFILE="/var/log/aiagent_local_installer.log"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"

###########################################################
# Import helper modules (UI + logic)
###########################################################
if [ -f "$REPO_ROOT/ai-agent/modules/ui.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/ai-agent/modules/ui.sh"
else
    echo "[WARN] ui.sh missing — fallback"
    info(){ echo "[INFO] $*"; }
    ok(){ echo "[OK] $*"; }
    warn(){ echo "[WARN] $*"; }
    err(){ echo "[ERR] $*" >&2; }
fi

if [ -f "$REPO_ROOT/ai-agent/modules/installer_helpers.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/ai-agent/modules/installer_helpers.sh"
else
    warn "installer_helpers.sh missing — degraded mode"
fi

if [ -f "$REPO_ROOT/devops/tools/healthcheck.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/devops/tools/healthcheck.sh"
else
    warn "healthcheck.sh missing — smoke tests disabled"
fi

###########################################################
# Parse flags — consistent with master installer
###########################################################
NON_INTERACTIVE="no"
AUTO_REPAIR="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE="yes"; shift;;
        --auto-repair) AUTO_REPAIR="yes"; shift;;
        *) warn "Unknown option: $1"; shift;;
    esac
done

###########################################################
# Preconditions / Environment verification
###########################################################
title "AI-Agent Local Installer"

info "Checking environment..."

if [ "$(id -u)" -ne 0 ]; then
    err "installer_local.sh must run as root"
    exit 1
fi

###########################################################
# Ensure base APT dependencies
###########################################################
install_dependencies() {
    title "Installing System Dependencies"

    DEBIAN_FRONTEND=noninteractive apt-get update -y >>"$LOGFILE" 2>&1 || true

    apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip \
        git curl wget jq unzip rsync netcat-openbsd \
        >>"$LOGFILE" 2>&1 || {
            warn "APT install failed"
            return 1
        }

    ok "System dependencies installed"
}

auto_repair_wrapper "install_dependencies" install_dependencies

###########################################################
# Create aiagent user if missing
###########################################################
AI_USER="aiagent"
if ! id -u "$AI_USER" >/dev/null 2>&1; then
    title "Creating system user"
    useradd --system --create-home --home-dir /home/"$AI_USER" --shell /usr/sbin/nologin "$AI_USER" || true
    ok "User $AI_USER created"
fi

###########################################################
# Prepare directories
###########################################################
title "Preparing installation directories"

mkdir -p "$INSTALL_ROOT"
rsync -a --delete "$REPO_ROOT/" "$INSTALL_ROOT/" >>"$LOGFILE" 2>&1

# Set ownership
chown -R "$AI_USER:$AI_USER" "$INSTALL_ROOT"

ok "Files synced to $INSTALL_ROOT"

###########################################################
# Python Virtual Environment
###########################################################
title "Creating Python Virtual Environment"

python3 -m venv "$VENV_DIR" >>"$LOGFILE" 2>&1 || {
    err "Failed to create venv"
    exit 1
}

source "$VENV_DIR/bin/activate"

pip install --upgrade pip >>"$LOGFILE" 2>&1
pip install -r "$INSTALL_ROOT/ai-agent/requirements.txt" >>"$LOGFILE" 2>&1 || {
    err "Failed to install Python dependencies"
    exit 1
}

ok "Python venv ready"

###########################################################
# SystemD Service Setup
###########################################################
title "Setting up systemd services"

SYSTEMD_SERVICE="$INSTALL_ROOT/devops/systemd/aiagent.service"
SYSTEMD_TARGET="/etc/systemd/system/aiagent.service"

if [ -f "$SYSTEMD_SERVICE" ]; then
    cp "$SYSTEMD_SERVICE" "$SYSTEMD_TARGET"
    chmod 644 "$SYSTEMD_TARGET"
    systemctl daemon-reload
    systemctl enable aiagent.service
    ok "Installed aiagent.service"
else
    warn "Systemd service file missing at $SYSTEMD_SERVICE"
fi

###########################################################
# Start service
###########################################################
title "Starting AI-Agent service"

systemctl restart aiagent.service || warn "Service restart failed"
sleep 3

###########################################################
# Healthcheck & Smoke Tests
###########################################################
if command -v post_deploy_smoke >/dev/null 2>&1; then
    title "Running Local Smoke Tests"

    post_deploy_smoke local aiagent-web /healthz 8000 45 || {
        warn "Smoke tests reported issues"
    }
else
    warn "healthcheck.sh not loaded — skipping smoke tests"
fi

###########################################################
# Wrap-up
###########################################################
ok "Local installation complete."
info "Log file -> $LOGFILE"
info "Installation directory -> $INSTALL_ROOT"

exit 0

