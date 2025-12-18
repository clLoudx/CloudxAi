#!/usr/bin/env bash
# Rebuild insert_modules_bundle.zip in deterministic mode

set -euo pipefail

REPO_ROOT="$(pwd)"


cd "$REPO_ROOT"

echo "==> Verifying required files..."
req=(
  "ai-agent/modules/ui.sh"
  "ai-agent/modules/healthcheck.sh"
  "ai-agent/modules/installer_helpers.sh"
  "devops/tools/post_deploy_smoke.sh"
)

for f in "${req[@]}"; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f"
    exit 1
  fi
done

echo "==> Removing old bundle..."
rm -f insert_modules_bundle.zip

echo "==> Creating deterministic zip..."
zip -X -r insert_modules_bundle.zip \
    ai-agent/modules/ui.sh \
    ai-agent/modules/healthcheck.sh \
    ai-agent/modules/installer_helpers.sh \
    devops/tools/post_deploy_smoke.sh

echo "==> ZIP content:"
unzip -l insert_modules_bundle.zip

echo "==> SHA256 checksum:"
sha256sum insert_modules_bundle.zip

