#!/usr/bin/env bash
# smoke_tests/smoke_check.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"

log(){ printf "==> %s\n" "$*"; }
err(){ printf "ERROR: %s\n" "$*" >&2; }
usage(){ cat <<EOF
Usage: $0 <mode>
Modes:
  local    - systemd/venv/local app checks
  docker   - docker-compose checks + http
  k8s      - kubernetes checks (namespace, deployment, ingress)
  ci       - run a sequence suited for CI (k8s then http)
EOF
exit 2
}

MODE="${1:-}"

if [ -z "$MODE" ]; then
  err "Missing mode"
  usage
fi

# ensure helper scripts are present
for f in check_http.sh check_imports.sh kubernetes_probe.sh docker_compose_check.sh ci_wrapper.sh; do
  if [ ! -x "$DIR/$f" ]; then
    err "Helper missing or not executable: $DIR/$f"
    exit 3
  fi
done

case "$MODE" in
  local)
    log "Running local smoke tests"
    "$DIR/check_imports.sh"
    "$DIR/check_http.sh" "127.0.0.1" 8000 /healthz
    ;;
  docker)
    log "Running docker-compose smoke tests"
    "$DIR/docker_compose_check.sh"
    "$DIR/check_http.sh" "127.0.0.1" 8000 /healthz
    ;;
  k8s)
    log "Running Kubernetes smoke tests"
    # default namespace and deployment; callers may wrap to call kubernetes_probe.sh directly
    NAMESPACE="${2:-aiagent}"
    SERVICE="${3:-aiagent-web}"
    "$DIR/kubernetes_probe.sh" "$NAMESPACE" "$SERVICE"
    ;;
  ci)
    log "Running CI wrapper"
    "$DIR/ci_wrapper.sh" k8s
    ;;
  *)
    err "Unknown mode: $MODE"
    usage
    ;;
esac

log "Smoke checks for mode '$MODE' completed OK"
exit 0

