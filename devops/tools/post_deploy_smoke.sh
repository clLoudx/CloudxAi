#!/usr/bin/env bash
#
# devops/tools/post_deploy_smoke.sh
# CLI wrapper around modules/healthcheck.sh -> post_deploy_smoke
# Supports:
#  --selftest                -> run local quick selfchecks (no cluster)
#  --namespace <ns>          -> k8s namespace or host for checks
#  --service <svc>           -> service name (k8s service or docker container)
#  --path <path>             -> HTTP path (default /healthz)
#  --port <port>             -> port number (default 8000)
#  --timeout <seconds>       -> overall timeout (default 60)
#
# Examples:
#  ./devops/tools/post_deploy_smoke.sh --selftest
#  ./devops/tools/post_deploy_smoke.sh --namespace aiagent --service aiagent-web --path /healthz --port 8000 --timeout 120
#

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"


#!/usr/bin/env bash
# wrapper around devops/tools/healthcheck.sh->post_deploy_smoke
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/healthcheck.sh"
if [ $# -lt 4 ]; then echo "Usage: $0 <target> <service> <path> <port> [timeout]"; exit 2; fi
post_deploy_smoke "$@"
  
  
  
# Source the healthcheck module if present
HC_MODULE="$REPO_ROOT/ai-agent/modules/healthcheck.sh"
# try alternative location
[ -f "$REPO_ROOT/modules/healthcheck.sh" ] && HC_MODULE="$REPO_ROOT/modules/healthcheck.sh"
if [ -f "$HC_MODULE" ]; then
  # shellcheck source=/dev/null
  . "$HC_MODULE"
else
  echo "WARN: healthcheck module not found at expected paths. Falling back to minimal checks."
fi

# Helper logging
_log(){ printf "%s\n" "$*"; }
_log_err(){ printf "ERROR: %s\n" "$*" >&2; }

# defaults
NAMESPACE=""
SERVICE=""
PATH_CHECK="/healthz"
PORT=8000
TIMEOUT=60
SELFTEST="no"

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST="yes"; shift;;
    --namespace) NAMESPACE="$2"; shift 2;;
    --service) SERVICE="$2"; shift 2;;
    --path) PATH_CHECK="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    -h|--help) echo "Usage: $0 [--selftest] [--namespace ns] [--service svc] [--path /healthz] [--port 8000] [--timeout 60]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# Selftest (local, CI-friendly quick checks)
if [ "$SELFTEST" = "yes" ]; then
  _log "Running selftest checks..."
  which curl >/dev/null 2>&1 || { _log_err "curl not available"; exit 2; }
  which python3 >/dev/null 2>&1 || _log "python3 not available (not required)"
  _log "Selftest OK (tools present)"
  exit 0
fi

# Ensure required args
if [ -z "$SERVICE" ]; then
  _log "No service supplied; defaulting to aiagent-web"
  SERVICE="${SERVICE:-aiagent-web}"
fi
if [ -z "$NAMESPACE" ]; then
  # treat as host mode if contains dot, else default to local
  _log "No namespace supplied; using host/local mode"
fi

_log "post_deploy_smoke: target=(ns:'$NAMESPACE' svc:'$SERVICE') path='$PATH_CHECK' port=$PORT timeout=$TIMEOUT"

# If kubectl present and namespace exists -> k8s mode
if command -v kubectl >/dev/null 2>&1 && [ -n "$NAMESPACE" ] && kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  _log "Kubernetes namespace detected: $NAMESPACE"
  # pick a pod (prefer label 'app' or first pod)
  pod=$(kubectl -n "$NAMESPACE" get pods -l "app=${SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -z "$pod" ]; then
    pod=$(kubectl -n "$NAMESPACE" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi
  if [ -z "$pod" ]; then
    _log_err "No pod found in namespace $NAMESPACE"
    exit 1
  fi
  _log "Using pod for port-forward: $pod"
  kubectl -n "$NAMESPACE" port-forward "$pod" "${PORT}:${PORT}" >/tmp/aiagent_pf_${pod}.log 2>&1 &
  pf_pid=$!
  # wait a bit for port-forward to establish
  sleep 1
  url="http://127.0.0.1:${PORT}${PATH_CHECK}"
  _log "Probing via port-forward -> $url"
  if http_check_with_retry "$url" 8 3 200; then
    _log "Smoke OK via port-forward"
    kill "$pf_pid" >/dev/null 2>&1 || true
    exit 0
  else
    _log_err "Smoke failed via port-forward"
    kill "$pf_pid" >/dev/null 2>&1 || true
    exit 2
  fi
fi

# Docker mode if container exists locally
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qE "^${SERVICE}$"; then
  _log "Detected docker container: $SERVICE"
  if docker_container_healthy "$SERVICE"; then
    # find published port
    published=$(docker port "$SERVICE" | awk -F'->' '{print $1}' | awk -F':' '{print $NF}' | head -n1 || true)
    if [ -n "$published" ]; then
      url="http://127.0.0.1:${published}${PATH_CHECK}"
      _log "Probing container at $url"
      if http_check_with_retry "$url" 8 3 200; then
        _log "Smoke OK (container published port)"
        exit 0
      else
        _log_err "Container published port did not respond"
        exit 2
      fi
    else
      _log "Container healthy but no published port found — assuming internal success"
      exit 0
    fi
  else
    _log_err "Container not healthy"
    exit 2
  fi
fi




# Fallback host mode
host="127.0.0.1"
url="http://${host}:${PORT}${PATH_CHECK}"
_log "Fallback HTTP probe -> $url"
if http_check_with_retry "$url" 8 3 200; then
  _log "Smoke OK (direct HTTP)"
  exit 0
else
  _log_err "Direct HTTP probe failed: $url"
  exit 2
fi

