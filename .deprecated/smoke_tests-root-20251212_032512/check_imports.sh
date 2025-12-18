#!/usr/bin/env bash
# smoke_tests/check_imports.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"

# Use venv in common locations
POTENTIAL_VENVS=("$PROJECT_ROOT/venv" "$PROJECT_ROOT/ai-agent/venv" "$PROJECT_ROOT/aiagent/venv" "$HOME/venv")
PYBIN="python3"

for v in "${POTENTIAL_VENVS[@]}"; do
  if [ -x "$v/bin/python" ]; then
    PYBIN="$v/bin/python"
    break
  fi
done

echo "Using python: $(command -v "$PYBIN")"

# Basic import list: adapt to your project modules
IMPORTS=(
  "flask"
  "redis"
  "rq"
  "requests"
  "ai"   # project package (adjust if different)
)

MISSING=()
for m in "${IMPORTS[@]}"; do
  if ! "$PYBIN" -c "import ${m}" >/dev/null 2>&1; then
    MISSING+=("$m")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Missing python imports: ${MISSING[*]}"
  echo "Try: $PYBIN -m pip install -r requirements.txt"
  exit 1
fi

echo "Python imports OK"
exit 0

