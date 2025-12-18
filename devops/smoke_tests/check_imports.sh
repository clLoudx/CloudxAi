#!/usr/bin/env bash
# Check that venv imports core libs work
# Usage: ./check_imports.sh /path/to/venv

set -o errexit
set -o nounset
set -o pipefail

VENV="${1:-/opt/ai-agent/venv}"
if [ ! -x "$VENV/bin/python" ]; then
  echo "Venv python missing: $VENV" >&2
  exit 2
fi

PY="$VENV/bin/python"
echo "Using $PY to import core modules..."

"$PY" - <<'PY'
import importlib,sys
reqs=['flask','redis','rq','requests']
missing=[r for r in reqs if importlib.util.find_spec(r) is None]
if missing:
    print("MISSING:"+",".join(missing))
    sys.exit(3)
print("OK: imports available")
PY

