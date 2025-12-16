#!/usr/bin/env bash
set -euo pipefail
# final_installer.sh - one-command installer for Ubuntu 22.04+
# WARNING: review before running. This script performs system-level changes.
# Usage: sudo ./final_installer.sh /opt/ai-agent your.domain.tld
PROJECT_DIR="${1:-/opt/ai-agent}"
DOMAIN="${2:-}"
echo "Final installer beginning. Project dir: $PROJECT_DIR"
echo "This script will create system user, copy files, create venv, install deps, and create systemd units."

# ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must be run as root (or with sudo). Exiting."
  exit 1
fi

# create system user
id -u aiagent >/dev/null 2>&1 || useradd --system --home /nonexistent --shell /usr/sbin/nologin aiagent || true

# copy project into place (assumes current dir contains project files)
mkdir -p "$PROJECT_DIR"
rsync -a --delete ./ "$PROJECT_DIR/"
chown -R root:root "$PROJECT_DIR"
mkdir -p /etc/ai-agent
echo "CREATE /etc/ai-agent/env with your secrets (OPENAI_API_KEY, API_KEY, REDIS_URL)"
cat > /etc/ai-agent/env <<'ENV'
# copy and edit secrets here
OPENAI_API_KEY=
API_KEY=
REDIS_URL=redis://127.0.0.1:6379/0
ENV
chmod 600 /etc/ai-agent/env
chown root:aiagent /etc/ai-agent/env || true

# create virtualenv and install deps
apt-get update
apt-get install -y python3-venv python3-pip python3-dev build-essential git nginx
sudo -u aiagent python3 -m venv "$PROJECT_DIR/venv"
export PATH="$PROJECT_DIR/venv/bin:$PATH"
pip install --upgrade pip
pip install -r "$PROJECT_DIR/requirements.txt"

# systemd unit for app (docker-compose recommended but we provide unit for venv gunicorn)
cat > /etc/systemd/system/aiagent-app.service <<'SERVICE'
[Unit]
Description=AI Agent App (Gunicorn)
After=network.target
[Service]
Type=simple
User=aiagent
Group=aiagent
WorkingDirectory=$PROJECT_DIR/dashboard
EnvironmentFile=/etc/ai-agent/env
ExecStart=$PROJECT_DIR/venv/bin/gunicorn -k eventlet -w 2 -b 0.0.0.0:8000 dashboard.app:app
Restart=on-failure
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable --now aiagent-app.service || true

# systemd unit for rq worker
cat > /etc/systemd/system/aiagent-rq.service <<'SERVICE2'
[Unit]
Description=AI Agent RQ Worker
After=network.target
[Service]
Type=simple
User=aiagent
Group=aiagent
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=/etc/ai-agent/env
ExecStart=$PROJECT_DIR/venv/bin/rq worker -u $REDIS_URL default
Restart=on-failure
[Install]
WantedBy=multi-user.target
SERVICE2
systemctl daemon-reload
systemctl enable --now aiagent-rq.service || true

# nginx site
cat > /etc/nginx/sites-available/aiagent <<'NGINX'
server {
  listen 80;
  server_name _;
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
    alias $PROJECT_DIR/dashboard/static/;
  }
  location /grafana/ {
    proxy_pass http://127.0.0.1:3000/;
  }
}
NGINX
ln -sf /etc/nginx/sites-available/aiagent /etc/nginx/sites-enabled/aiagent
nginx -t && systemctl reload nginx || true

echo "Installer finished. Review services: systemctl status aiagent-app aiagent-rq"
echo "Edit /etc/ai-agent/env to provide OPENAI_API_KEY and API_KEY before sending traffic."
