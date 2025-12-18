#!/usr/bin/env bash
# smoke_tests/ci_wrapper.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"

MODE="${1:-k8s}"

echo "::group::Smoke tests (mode=${MODE})"
if ! "$DIR/smoke_check.sh" "$MODE"; then
  echo "::endgroup::"
  echo "SMOKE TESTS FAILED (mode=${MODE})"
  exit 1
fi
echo "::endgroup::"
echo "SMOKE TESTS PASSED (mode=${MODE})"
exit 0

