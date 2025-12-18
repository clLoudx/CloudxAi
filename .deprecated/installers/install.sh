#!/usr/bin/env bash
#
# install.sh — Lightweight Wrapper for installer.sh
#
# Required for:
#   - deploy_from_zip.sh
#   - remote host automation
#   - legacy tooling
#   - simple "install this project" UX
#
# Always delegates REAL installation to installer.sh (max-logic version)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$REPO_ROOT/installer.sh"

if [ ! -f "$INSTALLER" ]; then
    echo "[ERR] installer.sh not found at: $INSTALLER" >&2
    exit 2
fi

chmod +x "$INSTALLER"

echo "[INFO] Running full installer..."
exec sudo "$INSTALLER" "$@"

