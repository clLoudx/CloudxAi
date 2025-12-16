#!/usr/bin/env bash
# build_release_zip.sh — produce deterministic release ZIP
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${REPO_ROOT}/aiagent_release_$(date +%Y%m%d_%H%M%S).zip}"
tmpd="$(mktemp -d)"
rsync -a --exclude='.git' --exclude='node_modules' "$REPO_ROOT/" "$tmpd/aiagent/" 
( cd "$tmpd" && zip -r -X "$OUT" aiagent >/dev/null )
echo "Built: $OUT"
exit 0

