#!/usr/bin/env bash
# smoke_tests/docker_compose_check.sh
set -euo pipefail
SELF="$(realpath "$0")"
DIR="$(dirname "$SELF")"

# prefer docker compose v2 (docker compose) else docker-compose
COMPOSE_CMD=""
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "docker compose not available"
  exit 2
fi

echo "Using compose command: $COMPOSE_CMD"

# Use project dir (assume repo root)
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
COMPOSE_FILE_CANDIDATES=( "$PROJECT_ROOT/docker-compose.yml" "$PROJECT_ROOT/docker-compose.prod.yml" "$PROJECT_ROOT/ai-agent/docker-compose.yml" )

COMPOSE_FILE=""
for f in "${COMPOSE_FILE_CANDIDATES[@]}"; do
  if [ -f "$f" ]; then COMPOSE_FILE="$f"; break; fi
done

if [ -z "$COMPOSE_FILE" ]; then
  echo "No docker-compose file found in expected locations"
  exit 3
fi

echo "Found compose file: $COMPOSE_FILE"

# bring up (non-blocking) health-check only if not running
$COMPOSE_CMD -f "$COMPOSE_FILE" ps --all >/dev/null 2>&1 || true

# ensure services are up
UP_COUNT=$($COMPOSE_CMD -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l || true)
if [ "$UP_COUNT" -lt 1 ]; then
  echo "No running services found. Attempting to start (detached)"
  $COMPOSE_CMD -f "$COMPOSE_FILE" up -d --remove-orphans
  sleep 4
fi

# check each container has status "running"
BAD=$($COMPOSE_CMD -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
TOTAL=$($COMPOSE_CMD -f "$COMPOSE_FILE" config --services | wc -l)

if [ "$BAD" -lt "$TOTAL" ]; then
  echo "Some services are not running; inspect: $COMPOSE_CMD -f $COMPOSE_FILE ps"
  $COMPOSE_CMD -f "$COMPOSE_FILE" ps
  exit 4
fi

# optional: check health status via docker inspect (if healthcheck exists)
for svc in $($COMPOSE_CMD -f "$COMPOSE_FILE" config --services); do
  cname=$($COMPOSE_CMD -f "$COMPOSE_FILE" ps -q "$svc" | head -n1)
  if [ -n "$cname" ]; then
    # check health status
    hs=$(docker inspect --format='{{json .State.Health}}' "$cname" 2>/dev/null || true)
    if [ -n "$hs" ] && [ "$hs" != "null" ]; then
      st=$(docker inspect --format='{{.State.Health.Status}}' "$cname" 2>/dev/null || true)
      echo "Container $svc health=$st"
      if [ "$st" = "unhealthy" ]; then
        echo "Container $svc reported unhealthy"
        docker logs --tail 50 "$cname" || true
        exit 5
      fi
    fi
  fi
done

echo "Docker Compose services appear healthy"
exit 0

