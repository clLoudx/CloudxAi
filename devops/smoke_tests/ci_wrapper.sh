#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
VENV="${1:-.venv}"

echo "Activating venv: $VENV"
. "$VENV/bin/activate"

echo "Running check_imports"
"$ROOT/devops/smoke_tests/check_imports.sh" "$VENV"

echo "Running HTTP check"
"$ROOT/devops/smoke_tests/check_http.sh" "http://127.0.0.1:8000/healthz" 20

if [ -x "$ROOT/devops/tools/post_deploy_smoke.sh" ]; then
  echo "Running post_deploy_smoke wrapper"
  "$ROOT/devops/tools/post_deploy_smoke.sh" 127.0.0.1 aiagent-web /healthz 8000 20
fi
echo "CI smoke wrapper finished."

