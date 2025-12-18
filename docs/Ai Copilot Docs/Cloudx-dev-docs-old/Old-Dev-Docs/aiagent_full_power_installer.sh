#!/usr/bin/env bash
# aiagent_full_power_installer.sh
# Full-power installer / repair / verifier for AI Agent project v1
# Use: sudo ./aiagent_full_power_installer.sh [command] [options]
# Commands: install | repair | verify | build_images | export_images | apply_patch | start | stop | status | logs | dlq_requeue | dlq_reset | pytest | backup | rollback | dry-run | help
set -euo pipefail
SELF="$(realpath "$0")"
ROOT_DIR="$(dirname "$SELF")"  # assume running from repo root or copy script into repo root
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/var/backups/aiagent_$TIMESTAMP"
ENV_DIR="/etc/ai-agent"
ENV_FILE="$ENV_DIR/env"
AI_USER="aiagent"
EXPORT_IMAGES_DIR="$ROOT_DIR/export_images"
PATCH_FILE="$ROOT_DIR/aiagent_release.patch"
PROM_RULES_SRC="$ROOT_DIR/deploy/alert_rules_generated.yml"
GRAFANA_DASHBOARDS_DIR="$ROOT_DIR/deploy/grafana/dashboards"
SYSTEMD_DIR="/etc/systemd/system"
NGINX_SITE="/etc/nginx/sites-available/ai-agent.conf"
LOG_DIR="/var/log/aiagent"
VENV_DIR="$ROOT_DIR/venv"

# helper
log(){ echo "==> $*"; }
err(){ echo "ERROR: $*" >&2; exit 1; }
confirm(){ read -p "$* [y/N]: " yn; case "$yn" in [Yy]*) return 0;; *) return 1;; esac; }

ensure_root(){
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root (sudo)"
  fi
}

# create backups of sensitive files
backup_if_exists(){
  local p="$1"
  if [ -e "$p" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$p" "$BACKUP_DIR/"
    log "Backed up $p -> $BACKUP_DIR/"
  fi
}

# create ai user
ensure_user(){
  if ! id -u "$AI_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /home/"$AI_USER" --shell /usr/sbin/nologin "$AI_USER"
    log "Created system user $AI_USER"
  else
    log "User $AI_USER exists"
  fi
}

# create env template if missing
ensure_env(){
  mkdir -p "$ENV_DIR"
  chmod 750 "$ENV_DIR"
  if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'ENV'
# /etc/ai-agent/env - required secrets (600)
# OPENAI_API_KEY=sk-...
# API_KEY=replace-with-admin
# REDIS_URL=redis://127.0.0.1:6379/0
# FLASK_SECRET=replace-with-random
ENV
    chmod 600 "$ENV_FILE"
    chown root:root "$ENV_FILE"
    log "Created template $ENV_FILE (edit and secure)"
  else
    log "$ENV_FILE exists (leave as is)"
  fi
}

# systemd units
install_systemd_units(){
  log "Installing systemd units..."
  local app_unit="$SYSTEMD_DIR/aiagent-app.service"
  local worker_unit="$SYSTEMD_DIR/aiagent-rq.service"
  backup_if_exists "$app_unit"
  backup_if_exists "$worker_unit"

  cat > "$app_unit" <<'UNIT'
[Unit]
Description=AI Agent Dashboard (Gunicorn)
After=network.target
Requires=network.target

[Service]
Type=simple
User=aiagent
Group=aiagent
WorkingDirectory=/opt/aiagent/dashboard
EnvironmentFile=/etc/ai-agent/env
ExecStart=/usr/bin/env bash -lc "source /opt/aiagent/venv/bin/activate || true; exec gunicorn dashboard.app:app -k eventlet -b 0.0.0.0:8000 --workers 3"
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
UNIT

  cat > "$worker_unit" <<'UNIT'
[Unit]
Description=AI Agent RQ Worker
After=network.target
Requires=network.target

[Service]
Type=simple
User=aiagent
Group=aiagent
WorkingDirectory=/opt/aiagent
EnvironmentFile=/etc/ai-agent/env
ExecStart=/usr/bin/env bash -lc "source /opt/aiagent/venv/bin/activate || true; exec rq worker -u ${REDIS_URL:-redis://127.0.0.1:6379/0} default"
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
UNIT

  chmod 644 "$app_unit" "$worker_unit"
  systemctl daemon-reload
  systemctl enable aiagent-app.service || true
  systemctl enable aiagent-rq.service || true
  log "Systemd units installed and enabled (not started)"
}

# nginx config template
install_nginx_template(){
  if ! command -v nginx >/dev/null 2>&1; then
    log "nginx not found; skipping nginx install"
    return
  fi
  backup_if_exists "$NGINX_SITE"
  cat > "$NGINX_SITE" <<'NGINX'
server {
  listen 80;
  server_name DOMAIN_PLACEHOLDER;

  location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location /static/ {
    alias /opt/aiagent/dashboard/static/;
  }

  location /metrics {
    allow 127.0.0.1;
    deny all;
    proxy_pass http://127.0.0.1:8000/metrics;
  }
}
NGINX
  sed -i "s/DOMAIN_PLACEHOLDER/_/g" "$NGINX_SITE"
  ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/ai-agent.conf
  nginx -t && systemctl reload nginx || log "nginx test/reload may have failed; check manually"
  log "Nginx template installed (edit server_name to your domain)"
}

# Build docker images if docker present
build_images(){
  if ! command -v docker >/dev/null 2>&1; then
    err "docker not installed on host"
  fi
  cd "$ROOT_DIR"
  if [ -f Dockerfile ]; then
    docker build -f Dockerfile -t aiagent_web:latest .
  fi
  if [ -f Dockerfile.worker ]; then
    docker build -f Dockerfile.worker -t aiagent_worker:latest .
  fi
  log "Docker build finished"
}

export_images(){
  mkdir -p "$EXPORT_IMAGES_DIR"
  if docker image inspect aiagent_web:latest >/dev/null 2>&1; then
    docker save aiagent_web:latest | gzip > "$EXPORT_IMAGES_DIR/aiagent_web_latest.tar.gz"
  fi
  if docker image inspect aiagent_worker:latest >/dev/null 2>&1; then
    docker save aiagent_worker:latest | gzip > "$EXPORT_IMAGES_DIR/aiagent_worker_latest.tar.gz"
  fi
  sha256sum "$EXPORT_IMAGES_DIR"/* > "$EXPORT_IMAGES_DIR/sha256_export_images.txt" || true
  log "Exported images to $EXPORT_IMAGES_DIR"
}

# apply git patch safely
apply_patch(){
  if [ ! -f "$PATCH_FILE" ]; then log "No patch file $PATCH_FILE"; return; fi
  if [ ! -d "$ROOT_DIR/.git" ]; then log "Not a git repo; skipping patch apply"; return; fi
  cd "$ROOT_DIR"
  git apply --stat "$PATCH_FILE"
  git apply --check "$PATCH_FILE" || { log "Patch does not cleanly apply"; return; }
  git checkout -b "patch/aiagent_apply_$(date +%s)"
  if git am --signoff "$PATCH_FILE"; then
    log "Patch applied via git am"
  else
    log "git am failed; attempting 3-way apply"
    git am --abort || true
    if git apply --3way "$PATCH_FILE"; then
      log "Applied with 3-way; please inspect and commit"
    else
      log "Patch could not be applied automatically; manual merge required"
    fi
  fi
}

# ensure venv and pip deps
ensure_venv_deps(){
  if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
  fi
  if [ -f "$ROOT_DIR/requirements.txt" ]; then
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install -r "$ROOT_DIR/requirements.txt"
  fi
  log "Virtualenv and dependencies are ready"
}

# start services (systemd)
start_services(){
  systemctl start aiagent-app || true
  systemctl start aiagent-rq || true
  log "Started services (check status via status command)"
}

stop_services(){
  systemctl stop aiagent-app || true
  systemctl stop aiagent-rq || true
  log "Stopped services"
}

status_services(){
  systemctl status aiagent-app --no-pager || true
  systemctl status aiagent-rq --no-pager || true
}

tail_logs(){
  journalctl -u aiagent-app -f &
  journalctl -u aiagent-rq -f &
}

# DLQ operations (requires redis-cli)
dlq_requeue(){
  local count="${1:-1}"
  if ! command -v redis-cli >/dev/null 2>&1; then err "redis-cli not available"; fi
  log "Requeueing up to $count items from DLQ->ai_tasks"
  for i in $(seq 1 "$count"); do
    item=$(redis-cli RPOP ai_tasks_dlq)
    if [ -z "$item" ]; then break; fi
    redis-cli LPUSH ai_tasks "$item"
  done
  log "Done. New ai_tasks length: $(redis-cli LLEN ai_tasks)"
}

dlq_reset(){
  if ! command -v redis-cli >/dev/null 2>&1; then err "redis-cli not available"; fi
  confirm "Are you sure you want to clear the DLQ (ai_tasks_dlq)? This is destructive." || return
  redis-cli DEL ai_tasks_dlq
  log "DLQ cleared"
}

# run tests
run_pytest(){
  if [ ! -d "$ROOT_DIR" ]; then err "Root dir missing"; fi
  if [ ! -d "$ROOT_DIR/venv" ]; then log "Activating environment from $VENV_DIR"; fi
  "$VENV_DIR/bin/pytest" -q || err "pytest failed"
}

# verify and smoke tests
verify(){
  log "Running verification checks..."
  # app health
  if curl -sS --fail http://127.0.0.1:8000/api/overview >/dev/null 2>&1; then
    log "App responded on 8000"
  else
    log "App did not respond on 8000 (it may not be running)"
  fi
  # metrics
  if curl -sS --fail http://127.0.0.1:8000/metrics >/dev/null 2>&1; then
    log "Metrics endpoint responding"
  else
    log "Metrics endpoint not responding"
  fi
  # systemd statuses
  status_services
  log "Verification complete"
}

# backup and rollback helpers
create_backup(){
  mkdir -p "$BACKUP_DIR"
  cp -a "$ROOT_DIR" "$BACKUP_DIR/aiagent_repo_backup_$TIMESTAMP"
  log "Created backup at $BACKUP_DIR"
}

rollback(){
  err "Rollback must be performed manually. Restore from backups in $BACKUP_DIR or previous artifact."
}

# repair actions
repair_all(){
  log "Starting repair routine..."
  ensure_user
  ensure_env
  ensure_venv_deps
  install_systemd_units
  install_nginx_template
  log "Repair routine finished. Please run verify and then start_services."
}

# usage
usage(){
  cat <<EOF
aiagent_full_power_installer.sh - full installer / repair tool for AI Agent
Usage: sudo $0 <command> [options]
Commands:
  install         - full install (create user, env, venv, systemd, nginx template)
  repair          - run repair routine (venv deps, systemd, nginx)
  verify          - run smoke checks and status
  build_images    - build docker images (requires docker)
  export_images   - save docker images to export_images/ and compute sha256
  apply_patch     - apply aiagent_release.patch if present
  start           - start systemd services (aiagent-app, aiagent-rq)
  stop            - stop services
  status          - show service status
  logs            - tail logs (background)
  dlq_requeue N   - requeue N items from DLQ
  dlq_reset       - clear DLQ (destructive)
  pytest          - run pytest in venv
  backup          - create repo backup under /var/backups
  rollback        - instructions to rollback (manual)
  dry-run         - show what would be done (not implemented separately)
  help            - show this help
EOF
}

# main
if [ $# -lt 1 ]; then usage; exit 1; fi
CMD="$1"; shift || true

case "$CMD" in
  install)
    ensure_root
    ensure_user
    ensure_env
    create_backup
    ensure_venv_deps
    install_systemd_units
    install_nginx_template
    log "Install finished. Edit $ENV_FILE and then start services."
    ;;
  repair)
    ensure_root
    repair_all
    ;;
  verify)
    verify
    ;;
  build_images)
    build_images
    ;;
  export_images)
    export_images
    ;;
  apply_patch)
    apply_patch
    ;;
  start)
    ensure_root
    start_services
    ;;
  stop)
    ensure_root
    stop_services
    ;;
  status)
    status_services
    ;;
  logs)
    tail_logs
    ;;
  dlq_requeue)
    dlq_requeue "$1"
    ;;
  dlq_reset)
    dlq_reset
    ;;
  pytest)
    run_pytest
    ;;
  backup)
    create_backup
    ;;
  rollback)
    rollback
    ;;
  dry-run)
    echo "Dry-run not separately implemented; run repair/install with manual inspection."
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: $CMD"
    usage
    ;;
esac
