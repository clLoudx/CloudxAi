#!/usr/bin/env bash
# smoke_tests/kubernetes_probe.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"

usage(){ cat <<EOF
Usage: $0 NAMESPACE SERVICE_LABEL [PORT] [PATH] [TIMEOUT_SECONDS]
Example:
  $0 aiagent aiagent-web 8000 /healthz 180
EOF
exit 2
}

if [ $# -lt 2 ]; then usage; fi

NAMESPACE="$1"
SERVICE="$2"
PORT="${3:-8000}"
PATH="${4:-/healthz}"
TIMEOUT="${5:-180}"

kubectl_ok(){ command -v kubectl >/dev/null 2>&1; }
if ! kubectl_ok; then echo "kubectl not present"; exit 2; fi

echo "Checking namespace: $NAMESPACE"
if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace $NAMESPACE not found"
  exit 3
fi

echo "Waiting for rollout of deployments with label app=$SERVICE"
kubectl -n "$NAMESPACE" rollout status deployment -l app="$SERVICE" --timeout="${TIMEOUT}s" || {
  echo "Rollout status failed"
  # continue to inspect pods
}

# locate a pod to test
POD=$(kubectl -n "$NAMESPACE" get pods -l app="$SERVICE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$POD" ]; then
  # fallback: pick any pod in ns
  POD=$(kubectl -n "$NAMESPACE" get pods --no-headers | awk '{print $1}' | head -n1 || true)
fi

if [ -z "$POD" ]; then
  echo "No pod found in namespace $NAMESPACE"
  exit 4
fi

echo "Selected pod: $POD"

# try in-cluster exec curl
if kubectl -n "$NAMESPACE" exec "$POD" -- /bin/sh -c "curl -fsS -m 5 http://127.0.0.1:${PORT}${PATH} >/dev/null" >/dev/null 2>&1 ; then
  echo "In-pod HTTP check OK"
  exit 0
fi

echo "In-pod HTTP check failed — attempting port-forward to localhost"

PF_LOCAL_PORT="$(shuf -i 20000-30000 -n 1)"
kubectl -n "$NAMESPACE" port-forward "$POD" "${PF_LOCAL_PORT}:${PORT}" >/tmp/smoke_pf_${POD}.log 2>&1 &
PF_PID=$!
# give it a moment
sleep 2

# wait for port to be ready
start_ts=$(date +%s)
while ! curl -fsS --max-time 3 "http://127.0.0.1:${PF_LOCAL_PORT}${PATH}" >/dev/null 2>&1; do
  now=$(date +%s)
  if [ $((now - start_ts)) -gt $TIMEOUT ]; then
    echo "Port-forward HTTP probe timed out"
    kill "$PF_PID" >/dev/null 2>&1 || true
    exit 5
  fi
  sleep 2
done

# success
kill "$PF_PID" >/dev/null 2>&1 || true
echo "Port-forward probe OK"
exit 0

