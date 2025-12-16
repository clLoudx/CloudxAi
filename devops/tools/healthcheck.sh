#!/usr/bin/env bash
#
# devops/tools/healthcheck.sh - Canonical healthcheck module
# Health checks, smoke tests and helpers for AI Agent installer
#
# Usage:
#   source devops/tools/healthcheck.sh
#   http_check_with_retry http://127.0.0.1:8000/healthz 5 5
#   systemd_service_ready aiagent-app 30
#   post_deploy_smoke aiagent aiagent-web /healthz 8000 60
#
set -o errexit
set -o nounset
set -o pipefail

# try to use logging functions if available
_log_info(){ command -v log_info >/dev/null 2>&1 && log_info "$@" || echo "INFO: $*"; }
_log_warn(){ command -v log_warn >/dev/null 2>&1 && log_warn "$@" || echo "WARN: $*"; }
_log_error(){ command -v log_error >/dev/null 2>&1 && log_error "$@" || echo "ERROR: $*"; }

# Default retry/backoff tuning (override before calling)
HC_RETRY_BASE=${HC_RETRY_BASE:-3}      # seconds
HC_RETRY_FACTOR=${HC_RETRY_FACTOR:-2}  # multiplier
HC_RETRY_MAX=${HC_RETRY_MAX:-120}      # maximum backoff seconds
HC_MAX_ATTEMPTS=${HC_MAX_ATTEMPTS:-8}  # attempts

# ---------------------------
# TCP check (host:port) with timeout and retries
# ---------------------------
tcp_check(){
  # tcp_check host port timeout_seconds
  local host="$1"; local port="$2"; local timeout="${3:-5}"
  if command -v nc >/dev/null 2>&1; then
    timeout "$timeout" bash -c "echo > /dev/tcp/${host}/${port}" >/dev/null 2>&1 && return 0 || return 1
  fi
  if command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1 && return 0 || return 1
  fi
  if command -v nc >/dev/null 2>&1; then
    nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1 && return 0 || return 1
  fi
  # fallback to curl if port maps to http endpoint
  return 1
}

# ---------------------------
# HTTP check with retries and optional expected status (200 by default)
# ---------------------------
http_check_with_retry(){
  # http_check_with_retry URL max_attempts initial_delay_seconds [expected_code]
  local url="$1"
  local max_attempts="${2:-$HC_MAX_ATTEMPTS}"
  local delay="${3:-$HC_RETRY_BASE}"
  local expected="${4:-200}"

  local attempt=0
  while [ $attempt -lt "$max_attempts" ]; do
    attempt=$((attempt+1))
    _log_info "HTTP check attempt #$attempt -> $url (expect $expected)"
    if command -v curl >/dev/null 2>&1; then
      # -sS fail will exit with non-zero on HTTP >=400 only with --fail
      if curl -sS --max-time 10 -o /tmp/hc_http_out.$$ -w "%{http_code}" "$url" >/tmp/hc_http_code.$$ 2>/dev/null; then
        http_code=$(cat /tmp/hc_http_code.$$ 2>/dev/null || echo "")
      else
        http_code=$(cat /tmp/hc_http_code.$$ 2>/dev/null || echo "")
      fi
      rm -f /tmp/hc_http_code.$$ /tmp/hc_http_out.$$ 2>/dev/null || true
      if [ "$http_code" = "$expected" ]; then
        _log_info "HTTP OK ($http_code): $url"
        return 0
      else
        _log_warn "HTTP check returned $http_code (expected $expected)"
      fi
    else
      _log_warn "curl not available for HTTP checks"
      return 2
    fi

    _log_info "Sleeping ${delay}s before next HTTP attempt..."
    sleep "$delay"
    delay=$(( delay * HC_RETRY_FACTOR ))
    [ $delay -gt $HC_RETRY_MAX ] && delay=$HC_RETRY_MAX
  done

  _log_error "HTTP check failed after $max_attempts attempts: $url"
  return 1
}

# ---------------------------
# TLS check: validates that TLS handshake works (uses openssl)
# ---------------------------
tls_check(){
  # tls_check host port
  local host="$1"; local port="${2:-443}"
  if command -v openssl >/dev/null 2>&1; then
    echo | openssl s_client -connect "${host}:${port}" -servername "$host" -brief >/dev/null 2>&1
    return $?
  else
    _log_warn "openssl not available for tls_check"
    return 2
  fi
}

# ---------------------------
# systemd readiness check for a service (waits until active)
# ---------------------------
systemd_service_ready(){
  # systemd_service_ready name timeout_seconds
  local svc="$1"; local timeout="${2:-30}"
  if ! command -v systemctl >/dev/null 2>&1; then
    _log_warn "systemctl not available"
    return 2
  fi
  local start_ts=$(date +%s)
  while true; do
    if systemctl is-active --quiet "$svc"; then
      _log_info "systemd service $svc is active"
      return 0
    fi
    now=$(date +%s)
    elapsed=$((now - start_ts))
    if [ $elapsed -ge "$timeout" ]; then
      _log_warn "service $svc did not become active within ${timeout}s"
      return 1
    fi
    sleep 2
  done
}

# ---------------------------
# Docker container health check
# ---------------------------
docker_container_healthy(){
  # docker_container_healthy container_name_or_id
  local cname="$1"
  if ! command -v docker >/dev/null 2>&1; then
    _log_warn "docker not installed"
    return 2
  fi
  if ! docker ps --format '{{.Names}}' | grep -qE "^${cname}$"; then
    _log_warn "docker container $cname not running"
    return 1
  fi
  # prefer health status if image defines HEALTHCHECK
  local status
  status=$(docker inspect --format='{{json .State.Health}}' "$cname" 2>/dev/null || echo "")
  if [ -n "$status" ] && [ "$status" != "null" ]; then
    # parse Status (may be "healthy" or "unhealthy")
    local st
    st=$(docker inspect --format='{{.State.Health.Status}}' "$cname" 2>/dev/null || echo "")
    if [ "$st" = "healthy" ]; then
      _log_info "container $cname health=healthy"
      return 0
    else
      _log_warn "container $cname health=$st"
      return 1
    fi
  fi
  # fallback: try running a quick command inside container (if possible)
  if docker exec "$cname" true >/dev/null 2>&1; then
    _log_info "container $cname responding to exec"
    return 0
  fi
  _log_warn "container $cname not healthy"
  return 1
}

# ---------------------------
# Compose file healthcheck helper snippet generator (returns snippet to stdout)
# ---------------------------
generate_compose_healthcheck_snippet(){
  # usage: generate_compose_healthcheck_snippet "/healthz" 8000  "curl -fsS http://localhost:8000/healthz || exit 1"
  local path="${1:-/healthz}"; local port="${2:-8000}"; local cmd="${3:-curl -fsS http://localhost:${port}${path} || exit 1}"
  cat <<EOF
healthcheck:
  test: ["CMD-SHELL", "${cmd}"]
  interval: 30s
  timeout: 5s
  retries: 3
EOF
}

# ---------------------------
# k8s liveness/readiness snippet generator (YAML fragment)
# ---------------------------
generate_k8s_probe_yaml(){
  # generate_k8s_probe_yaml path port (httpGet) readiness/liveness default values
  local path="${1:-/healthz}"; local port="${2:-8000}"; local initialDelay="${3:-10}"; local period="${4:-10}"
  cat <<EOF
livenessProbe:
  httpGet:
    path: "${path}"
    port: ${port}
  initialDelaySeconds: ${initialDelay}
  periodSeconds: ${period}
  timeoutSeconds: 5
readinessProbe:
  httpGet:
    path: "${path}"
    port: ${port}
  initialDelaySeconds: ${initialDelay}
  periodSeconds: ${period}
  timeoutSeconds: 5
EOF
}

# ---------------------------
# post_deploy_smoke - combined smoke test used by installer
# ---------------------------
post_deploy_smoke(){
  # post_deploy_smoke <namespace-or-host> <service-or-container> <path> <port> <timeout_seconds>
  # If namespace looks like kube namespace and kubectl present, will try to curl service inside cluster via port-forward OR check ingress
  local target="$1"     # namespace or host depending on mode
  local service="$2"    # name of service or container or deployment
  local path="${3:-/healthz}"
  local port="${4:-8000}"
  local timeout_secs="${5:-60}"

  _log_info "Starting post-deploy smoke: target=${target} service=${service} path=${path} port=${port} timeout=${timeout_secs}"

  local start_ts=$(date +%s)
  local attempt=0
  local url=""
  # If kubectl exists and target looks like a namespace, try k8s mode
  if command -v kubectl >/dev/null 2>&1 && kubectl get ns "${target}" >/dev/null 2>&1 2>/dev/null; then
    # Try to access service via cluster IP: use kubectl port-forward as fallback
    _log_info "Detected Kubernetes namespace ${target}; attempting port-forward to service/${service}"
    # find a pod to port-forward
    local pod
    pod=$(kubectl -n "${target}" get pods -l "app=${service},app.kubernetes.io/name=${service}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -z "$pod" ]; then
      pod=$(kubectl -n "${target}" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi
    if [ -z "$pod" ]; then
      _log_warn "No pod found in namespace ${target} to port-forward"
    else
      # run port-forward in background on an ephemeral local port
      local pf_port="${port}"
      _log_info "Starting kubectl port-forward ${pod} ${pf_port}:${port} (background)"
      kubectl -n "${target}" port-forward "${pod}" "${pf_port}:${port}" >/tmp/aiagent_pf_${pod}.log 2>&1 &
      local pf_pid=$!
      # give it a moment
      sleep 1
      url="http://127.0.0.1:${pf_port}${path}"
      # run HTTP check loop
      while true; do
        attempt=$((attempt+1))
        if http_check_with_retry "$url" 1 2 200; then
          _log_info "Smoke succeeded via port-forward -> $url"
          kill "$pf_pid" >/dev/null 2>&1 || true
          return 0
        fi
        now=$(date +%s)
        elapsed=$((now - start_ts))
        if [ "$elapsed" -ge "$timeout_secs" ]; then
          _log_warn "Smoke timed out after ${timeout_secs}s"
          kill "$pf_pid" >/dev/null 2>&1 || true
          return 1
        fi
        sleep 2
      done
    fi
  fi

  # Non-k8s mode: if service looks like host (contains dot) or target looks like host, prefer direct HTTP
  if [[ "$target" =~ \. ]] || [[ "$service" =~ \. ]]; then
    # treat target as host
    url="http://${target}:${port}${path}"
    _log_info "Using direct URL $url"
    if http_check_with_retry "$url" $HC_MAX_ATTEMPTS $HC_RETRY_BASE 200; then
      _log_info "Smoke check OK: $url"
      return 0
    else
      _log_warn "Smoke failed for $url"
      return 1
    fi
  fi

  # If docker present and service corresponds to a container, try container check and then curl via localhost if port published
  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qE "^${service}$"; then
    _log_info "Detected docker container ${service}; checking health"
    if docker_container_healthy "$service"; then
      # try published ports
      local published
      published=$(docker port "$service" | awk -F'->' '{print $1}' | awk -F':' '{print $NF}' | head -n1 || true)
      if [ -n "$published" ]; then
        url="http://127.0.0.1:${published}${path}"
        _log_info "Attempting HTTP check at $url (container published)"
        if http_check_with_retry "$url" $HC_MAX_ATTEMPTS $HC_RETRY_BASE 200; then
          _log_info "Smoke OK: $url"
          return 0
        fi
      fi
      _log_info "Container healthy but no published port succeeded"
      return 0
    else
      _log_warn "Container $service not healthy"
      return 1
    fi
  fi

  # fallback: try local http check using target as host
  url="http://${target}:${port}${path}"
  _log_info "Fallback URL: $url"
  if http_check_with_retry "$url" $HC_MAX_ATTEMPTS $HC_RETRY_BASE 200; then
    _log_info "Smoke OK: $url"
    return 0
  fi

  _log_error "post_deploy_smoke: all methods failed for target=${target} service=${service}"
  return 1
}

# ---------------------------
# Small helper: wait for port listening on host:port (used by installer)
# ---------------------------
wait_for_port(){
  # wait_for_port host port timeout_seconds
  local host="$1"; local port="$2"; local timeout="${3:-30}"
  local start=$(date +%s)
  while true; do
    if tcp_check "$host" "$port" 3; then
      _log_info "Port ${host}:${port} is reachable"
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      _log_warn "Timeout waiting for ${host}:${port}"
      return 1
    fi
    sleep 1
  done
}

# ---------------------------
# Export functions for sourcing scripts
# ---------------------------
export -f tcp_check http_check_with_retry tls_check systemd_service_ready \
           docker_container_healthy generate_compose_healthcheck_snippet \
           generate_k8s_probe_yaml post_deploy_smoke wait_for_port

# auto-run a small self-test when run directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "devops/tools/healthcheck.sh self-test: Checking http://127.0.0.1:8000/healthz (short)"
  http_check_with_retry http://127.0.0.1:8000/healthz 2 1 200 || echo "Check failed (expected when service absent)"
fi
