#!/usr/bin/env bash
# smoke_tests/check_http.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"

usage(){ cat <<EOF
Usage: $0 HOST PORT PATH [EXPECTED_CODE] [MAX_ATTEMPTS]
Example:
  $0 127.0.0.1 8000 /healthz 200 8
EOF
exit 2
}

if [ $# -lt 3 ]; then usage; fi

HOST="$1"
PORT="$2"
PATH="${3#/}"   # strip leading slash
EXPECTED="${4:-200}"
MAX_ATTEMPTS="${5:-8}"
DELAY=2

curl_cmd() {
  # use http:// for plain, assume http for local; allow https if port==443
  if [ "$PORT" -eq 443 ]; then
    proto="https"
  else
    proto="http"
  fi
  url="${proto}://${HOST}:${PORT}/${PATH}"
  # use --fail to return non-zero on 4xx/5xx
  HTTP_CODE=$(curl -sS --max-time 10 -o /tmp/smoke_http_out.$$ -w "%{http_code}" "$url" || true)
  echo "$HTTP_CODE"
}

attempt=1
while [ $attempt -le "$MAX_ATTEMPTS" ]; do
  printf "HTTP probe attempt %d/%d -> %s:%s/%s ... " "$attempt" "$MAX_ATTEMPTS" "$HOST" "$PORT" "$PATH"
  code=$(curl_cmd)
  if [ "$code" = "$EXPECTED" ]; then
    echo "OK ($code)"
    rm -f /tmp/smoke_http_out.$$ || true
    exit 0
  else
    echo "got $code (expected $EXPECTED)"
  fi
  attempt=$((attempt+1))
  sleep $DELAY
  DELAY=$(( DELAY * 2 ))
  [ $DELAY -gt 30 ] && DELAY=30
done

err(){ printf "ERROR: %s\n" "$*"; }
err "HTTP probe failed after $MAX_ATTEMPTS attempts (last code: $code)"
[ -f /tmp/smoke_http_out.$$ ] && { echo "--- response body ---"; sed -n '1,200p' /tmp/smoke_http_out.$$; }
exit 1

