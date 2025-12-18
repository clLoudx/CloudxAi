#!/usr/bin/env bash
#
# build_final_zip.sh — Deterministic ZIP builder for the AI Agent Repo
# Max-Logic Mode (no contradictions — full reasoning consistency)
#
# Output:
#   aiagent_release_YYYYMMDD_HHMM.zip
#
set -o errexit
set -o nounset
set -o pipefail

############################################
# ANSI colors
############################################
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

############################################
# Utility: timestamp
############################################
ts() { date +"%Y-%m-%d %H:%M:%S"; }

############################################
# Logging functions
############################################
info()  { echo -e "${BLUE}[INFO]${NC}  $(ts)  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $(ts)  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $(ts)  $*" >&2; }
err()   { echo -e "${RED}[ERR]${NC}   $(ts)  $*" >&2; exit 1; }

############################################
# Determine repo root dynamically
############################################
REPO_ROOT="$(pwd)"
info "Using project root: $REPO_ROOT"

############################################
# Validate structure (Max-Logic)
############################################
[ -d "$REPO_ROOT/ai-agent" ]      || err "Missing ai-agent/"
[ -d "$REPO_ROOT/devops" ]        || err "Missing devops/"
[ -d "$REPO_ROOT/charts" ]        || err "Missing charts/"
[ -f "$REPO_ROOT/installer.sh" ]  || err "Missing installer.sh"

ok "Repository structure validated"

############################################
# Build deterministic ZIP filename
############################################
OUT_NAME="aiagent_release_$(date +%Y%m%d_%H%M).zip"
OUT_PATH="$REPO_ROOT/$OUT_NAME"

info "Output file will be: $OUT_PATH"

############################################
# Clean old zip files (optional)
############################################
if ls "$REPO_ROOT"/aiagent_release_*.zip >/dev/null 2>&1; then
    warn "Old release files detected — removing them for determinism"
    rm -f "$REPO_ROOT"/aiagent_release_*.zip
fi

############################################
# Create ZIP (deterministic ordering)
############################################
info "Creating ZIP archive..."

(
    cd "$REPO_ROOT"

    # Using zip with fixed ordering
    zip -r "$OUT_PATH" \
        ai-agent \
        devops \
        charts \
        github_actions \
        .github \
        installer.sh \
        installer-helm-deploy.sh \
        auto-bootstrap-aiagent.sh \
        build_and_bundle.sh \
        generate_devops_and_files.sh \
        tools \
        smoke_tests \
        service-repair.sh \
        verify_and_repair.sh \
        upgrade.sh \
        uninstaller.sh \
        README.txt \
        -x "*.DS_Store" \
        -x "__MACOSX" \
        -x "*.pyc" \
        -x "*.o"
)

ok "Archive successfully created"

############################################
# Show result summary
############################################
echo ""
info "=========================================================="
info "ZIP Ready:"
echo -e "    ${GREEN}${OUT_PATH}${NC}"
info "=========================================================="

