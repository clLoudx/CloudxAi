#!/usr/bin/env bash
#
# service-repair.sh — targeted repair for systemd/docker/redis/apps
# - Diagnostics, optional auto repairs, repair bundle creation
# - Flags: --auto (attempt automatic repairs), --bundle (create tarball of logs)
#
set -o errexit
set -o nounset
set -o pipefail

RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; CYAN="\033[1;36m"; NC="\033[0m"
info(){ echo -e "${BLUE}➤${NC} $*"; } ; ok(){ echo -e "${GREEN}✔${NC} $*"; } ; warn(){ echo -e "${YELLOW}⚠${NC} $*"; } ; err(){ echo -e "${RED}✘${NC} $*" >&2; }

LOG="/var/log/aiagent-service-repair.log"
BUNDLE_DIR="/tmp/aiagent-repair-$(date +%Y%m%d_%H%M%S)"
AUTO="no"; BUNDLE="no"
SERVICE_APP="aiagent-app.service"; SERVICE_WORKER="aiagent-rq.service"; REDIS="aiagent-redis"

while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO="yes"; shift;;
    --bundle) BUNDLE="yes"; shift;;
    -h|--help) echo "Usage: $0 [--auto] [--bundle]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

section(){ echo -e "\n${CYAN}========== $* ==========${NC}\n"; }

section "Service Repair - Diagnostics"
systemctl status "$SERVICE_APP" --no-pager >> "$LOG" 2>&1 || true
systemctl status "$SERVICE_WORKER" --no-pager >> "$LOG" 2>&1 || true
journalctl -u "$SERVICE_APP" -n 200 --no-pager >> "$LOG" 2>&1 || true
journalctl -u "$SERVICE_WORKER" -n 200 --no-pager >> "$LOG" 2>&1 || true

if command -v docker >/dev/null 2>&1; then
  docker ps -a >> "$LOG" 2>&1 || true
  if docker ps --format '{{.Names}}' | grep -q "^${REDIS}$"; then
    info "Found redis container $REDIS"
    if docker exec "$REDIS" redis-cli ping >/dev/null 2>&1; then ok "Redis PONG"; else warn "Redis not responding"; fi
  else
    warn "Redis container not present"
  fi
else
  warn "Docker missing"
fi

# Auto repair if requested
if [ "$AUTO" = "yes" ]; then
  section "AUTO-REPAIR MODE"
  if ! systemctl is-active --quiet "$SERVICE_APP"; then
    warn "Attempting restart: $SERVICE_APP"
    systemctl restart "$SERVICE_APP" || warn "Restart failed; check journal"
  fi
  if ! systemctl is-active --quiet "$SERVICE_WORKER"; then
    warn "Attempting restart: $SERVICE_WORKER"
    systemctl restart "$SERVICE_WORKER" || warn "Restart failed; check journal"
  fi
  if command -v docker >/dev/null 2>&1; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${REDIS}$"; then
      warn "Creating redis container"
      docker run -d --name "$REDIS" --restart unless-stopped -p 127.0.0.1:6379:6379 redis:7 >> "$LOG" 2>&1 || warn "docker run failed"
      ok "Redis container started (attempted)"
    fi
  fi
fi

if [ "$BUNDLE" = "yes" ]; then
  mkdir -p "$BUNDLE_DIR"
  cp -a /var/log/ai-agent-*.log "$BUNDLE_DIR/" 2>/dev/null || true
  journalctl -u "$SERVICE_APP" -n 500 --no-pager > "$BUNDLE_DIR/app_journal.log" 2>/dev/null || true
  journalctl -u "$SERVICE_WORKER" -n 500 --no-pager > "$BUNDLE_DIR/worker_journal.log" 2>/dev/null || true
  tar -czf "${BUNDLE_DIR}.tar.gz" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")" || true
  ok "Repair bundle created: ${BUNDLE_DIR}.tar.gz"
fi

section "Service repair finished. See $LOG"
exit 0

