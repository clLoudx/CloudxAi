#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
TARGET="$ROOT_DIR/.github/workflows"

echo "==> Creating GitHub Actions directory with safe permissions..."

# if directory exists but broken
if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
  echo "!! Found conflicting file named .github/workflows — renaming it"
  mv "$TARGET" "${TARGET}_backup_$(date +%s)"
fi

# force create
sudo mkdir -p "$TARGET"

# fix ownership (you become owner)
sudo chown -R "$USER":"$USER" "$ROOT_DIR/.github"

# set safe permissions
chmod -R 0775 "$ROOT_DIR/.github"

echo "==> Done. Directory ready:"
echo "    $TARGET"
echo "==> You can now add YAML workflows."

