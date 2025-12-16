#!/usr/bin/env bash
# auto-bootstrap-aiagent.sh
# Create venv, install pip reqs, build frontend, ensure systemd units exist.
set -euo pipefail
SELF="$(realpath "$0")"
ROOT_DIR="$(dirname "$SELF")"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "$LOG_DIR" /var/log || true
LOG="${LOG_DIR}/auto-bootstrap-$(date +%Y%m%d_%H%M%S).log"

echo "[$(date -Iseconds)] auto-bootstrap starting" >> "$LOG"

VENV_DIR="${ROOT_DIR}/venv"
REQ_FILE="${ROOT_DIR}/requirements.txt"
FRONTEND_DIR="${ROOT_DIR}/frontend"
SYSTEMD_DIR="/etc/systemd/system"
APP_UNIT="$SYSTEMD_DIR/aiagent-app.service"
WORKER_UNIT="$SYSTEMD_DIR/aiagent-rq.service"
ENV_DIR="/etc/ai-agent"
ENV_FILE="$ENV_DIR/env"
EMERGENCY_TOOL="${ROOT_DIR}/tools/emergency-total-repair.sh"

# Helpers
log(){ echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }
warn(){ echo "[$(date -Iseconds)] WARNING: $*" | tee -a "$LOG" >&2; }
err(){ echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG" >&2; exit 1; }
safe_exec(){ echo "RUN: $*"; eval "$@" >> "$LOG" 2>&1; }

log "ROOT_DIR=$ROOT_DIR"

# 1) Ensure python3 present
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 not found — please install system python first (apt install python3)"
fi

# 2) Create env template if missing
mkdir -p "$ENV_DIR"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'ENV'
# /etc/ai-agent/env - edit with secrets (chmod 600)
# OPENAI_API_KEY=
# API_KEY=
# REDIS_URL=redis://127.0.0.1:6379/0
# FLASK_SECRET=
ENV
  chmod 600 "$ENV_FILE" || true
  log "Created $ENV_FILE (please edit secrets)"
else
  log "$ENV_FILE exists — preserving"
fi

# 3) Build/create venv safely
if [ -d "$VENV_DIR" ]; then
  log "Venv exists at $VENV_DIR — moving to backup and recreating"
  mv "$VENV_DIR" "${VENV_DIR}.bak.$(date +%s)" || true
fi

log "Creating venv at $VENV_DIR"
python3 -m venv "$VENV_DIR" >> "$LOG" 2>&1 || {
  warn "venv creation failed — attempting emergency repair"
  [ -x "$EMERGENCY_TOOL" ] && sudo bash "$EMERGENCY_TOOL" --full-auto --venv-path "$VENV_DIR" || true
  python3 -m venv "$VENV_DIR" >> "$LOG" 2>&1 || err "venv creation failed after repair"
}

log "Upgrading pip inside venv"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel >> "$LOG" 2>&1 || warn "pip upgrade failed"

# 4) Install requirements if present
if [ -f "$REQ_FILE" ]; then
  log "Installing pip requirements from $REQ_FILE"
  if ! "$VENV_DIR/bin/pip" install --no-cache-dir -r "$REQ_FILE" >> "$LOG" 2>&1; then
    warn "pip install encountered errors — attempting to detect build deps"
    tail -n 200 "$LOG" | sed -n '1,200p' >> "$LOG"
    # best-effort install build deps
    if command -v apt-get >/dev/null 2>&1; then
      log "Installing build-essential & headers via apt"
      sudo DEBIAN_FRONTEND=noninteractive apt-get update >> "$LOG" 2>&1 || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential python3-dev libssl-dev libffi-dev rustc cargo >> "$LOG" 2>&1 || true
      "$VENV_DIR/bin/pip" install --no-cache-dir -r "$REQ_FILE" >> "$LOG" 2>&1 || warn "pip still failed"
    fi
  fi
else
  log "No requirements.txt found; skipping pip install"
fi

# 5) Build frontend (if exists)
if [ -d "$FRONTEND_DIR" ] && [ -f "$FRONTEND_DIR/package.json" ]; then
  log "Building frontend in $FRONTEND_DIR"
  # prefer yarn/npm pnpm? detect package manager
  pushd "$FRONTEND_DIR" >/dev/null
  if command -v pnpm >/dev/null 2>&1; then
    safe_exec "pnpm install --shamefully-hoist"
    safe_exec "pnpm run build"
  elif command -v yarn >/dev/null 2>&1; then
    safe_exec "yarn install --frozen-lockfile"
    safe_exec "yarn build"
  else
    safe_exec "npm ci || npm install"
    safe_exec "npm run build || npm run build --if-present"
  fi
  popd >/dev/null
else
  log "No frontend found at $FRONTEND_DIR — skipping frontend build"
fi

# 6) Create systemd units if missing (conservative)
if [ ! -f "$APP_UNIT" ] || [ ! -f "$WORKER_UNIT" ]; then
  log "Creating conservative systemd units in /etc/systemd/system/"
  sudo mkdir -p /etc/ai-agent || true
  sudo tee "$APP_UNIT" > /dev/null <<EOF
[Unit]
Description=AI Agent Dashboard (generated)
After=network.target

[Service]
User=aiagent
WorkingDirectory=/opt/ai-agent/dashboard
EnvironmentFile=/etc/ai-agent/env
ExecStart=$VENV_DIR/bin/gunicorn dashboard.app:app -k eventlet -b 0.0.0.0:8000 --workers 2
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  sudo tee "$WORKER_UNIT" > /dev/null <<EOF
[Unit]
Description=AI Agent RQ Worker (generated)
After=network.target

[Service]
User=aiagent
WorkingDirectory=/opt/ai-agent
EnvironmentFile=/etc/ai-agent/env
ExecStart=/bin/bash -lc "source $VENV_DIR/bin/activate; exec rq worker -u \${REDIS_URL:-redis://127.0.0.1:6379/0} default"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  sudo chmod 644 "$APP_UNIT" "$WORKER_UNIT"
  sudo systemctl daemon-reload || true
  sudo systemctl enable --now aiagent-app.service aiagent-rq.service || true
  log "Systemd units created and enabled (best-effort)"
else
  log "Systemd units already present — leaving intact"
fi

# 7) Minimal /healthz route suggestion
# If backend is Flask and file exists, print instructions to add route.
FLASK_APP_FILE="${ROOT_DIR}/dashboard/app.py"
if [ -f "$FLASK_APP_FILE" ]; then
  log "Detected possible Flask app at $FLASK_APP_FILE — ensure /healthz route exists."
  grep -q "def healthz" "$FLASK_APP_FILE" || {
    cat >> "$FLASK_APP_FILE" <<'PY'
# Added healthz endpoint for liveness/readiness probes
from flask import jsonify

@app.route("/healthz")
def healthz():
    return jsonify(status="ok"), 200
PY
    log "Appended /healthz to $FLASK_APP_FILE (please review and adjust imports if necessary)"
  }
fi

log "auto-bootstrap done; log: $LOG"
echo "AUTO-BOOTSTRAP COMPLETE (log: $LOG)"
exit 0

