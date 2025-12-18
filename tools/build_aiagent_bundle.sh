#!/usr/bin/env bash
# build_aiagent_bundle.sh
# Generates aiagent_bundle/ with frontend, devops, tools, installer, health snippet, CI skeleton and packaging.
set -euo pipefail

ROOT="aiagent_bundle"
OUT_TAR="${ROOT}.tar.gz"
OUT_ZIP="${ROOT}.zip"
echo ">>> Building AI Agent bundle in ./${ROOT}"

# cleanup
rm -rf "$ROOT" "$OUT_TAR" "$OUT_ZIP"
mkdir -p "$ROOT"

# helper to write files
write_file() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
'"$@"'
EOF
}

# But above helper won't expand variable content passed; we'll use direct cat <<'EOF' sections below.

############
# FRONTEND
############
mkdir -p "$ROOT/frontend/src/components" "$ROOT/frontend/public"

cat > "$ROOT/frontend/package.json" <<'EOF'
{
  "name": "aiagent-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest"
  },
  "dependencies": {
    "axios": "^1.4.0",
    "clsx": "^1.2.1",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.0.0",
    "autoprefixer": "^10.4.14",
    "postcss": "^8.4.21",
    "tailwindcss": "^3.4.0",
    "vite": "^5.0.0",
    "vitest": "^0.34.6",
    "@testing-library/react": "^14.0.0",
    "@testing-library/jest-dom": "^6.0.0"
  }
}
EOF

cat > "$ROOT/frontend/vite.config.js" <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: { port: 5173, strictPort: true }
})
EOF

cat > "$ROOT/frontend/tailwind.config.js" <<'EOF'
module.exports = {
  content: ['./index.html','./src/**/*.{js,jsx}'],
  theme: { extend: {} },
  plugins: []
}
EOF

cat > "$ROOT/frontend/public/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1.0" />
  <title>AI Agent — Multi-Project Chat</title>
</head>
<body class="antialiased bg-slate-900 text-slate-100">
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

cat > "$ROOT/frontend/src/main.jsx" <<'EOF'
import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './index.css'
createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>)
EOF

cat > "$ROOT/frontend/src/index.css" <<'EOF'
@tailwind base; @tailwind components; @tailwind utilities;
html,body,#root{height:100%}
body{font-family:Inter,ui-sans-serif,system-ui;-webkit-font-smoothing:antialiased}
EOF

cat > "$ROOT/frontend/src/App.jsx" <<'EOF'
import React from 'react'
export default function App(){ return <div className="h-screen flex items-center justify-center text-white">AI Agent Frontend (placeholder)</div> }
EOF

############
# HELM CHARTS
############
mkdir -p "$ROOT/devops/helm/aiagent-web/templates" "$ROOT/devops/helm/aiagent-worker/templates"

cat > "$ROOT/devops/helm/aiagent-web/Chart.yaml" <<'EOF'
apiVersion: v2
name: aiagent-web
description: Helm chart for AI Agent Web
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

cat > "$ROOT/devops/helm/aiagent-web/values.yaml" <<'EOF'
image:
  repository: ghcr.io/your-org/aiagent_web
  tag: latest
service:
  port: 8000
ingress:
  enabled: true
  host: your.domain.com
  tls:
    enabled: true
    secretName: aiagent-tls
EOF

cat > "$ROOT/devops/helm/aiagent-web/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aiagent-web
spec:
  replicas: 1
  selector:
    matchLabels: { app: aiagent-web }
  template:
    metadata:
      labels: { app: aiagent-web }
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports: [{ containerPort: {{ .Values.service.port }} }]
          readinessProbe:
            httpGet: { path: /healthz, port: {{ .Values.service.port }} }
EOF

cat > "$ROOT/devops/helm/aiagent-worker/Chart.yaml" <<'EOF'
apiVersion: v2
name: aiagent-worker
description: Helm chart for AI Agent Worker
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

cat > "$ROOT/devops/helm/aiagent-worker/values.yaml" <<'EOF'
image:
  repository: ghcr.io/your-org/aiagent_worker
  tag: latest
EOF

cat > "$ROOT/devops/helm/aiagent-worker/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aiagent-worker
spec:
  replicas: 1
  selector:
    matchLabels: { app: aiagent-worker }
  template:
    metadata:
      labels: { app: aiagent-worker }
    spec:
      containers:
        - name: worker
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
EOF

############
# tools/emergency-total-repair.sh (advanced version)
############
mkdir -p "$ROOT/tools"

cat > "$ROOT/tools/emergency-total-repair.sh" <<'EOF'
#!/usr/bin/env bash
#
# tools/emergency-total-repair.sh
# Advanced emergency total repair (safe-first, idempotent)
#
set -o errexit
set -o nounset
set -o pipefail

LOG="/var/log/aiagent-emergency-repair.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"

echo "[$(date --iso-8601=seconds)] Emergency repair started" >> "$LOG"
echo "Emergency Repair (advanced) starting. Check $LOG for details."

# safe helpers
_info(){ echo "➤ $*" | tee -a "$LOG"; }
_ok(){ echo "✔ $*" | tee -a "$LOG"; }
_warn(){ echo "⚠ $*" | tee -a "$LOG"; }
_err(){ echo "✘ $*" | tee -a "$LOG"; }

# 1) kill stuck locks/processes
_info "Killing apt/dpkg processes (if any)"
pids=$(pgrep -af 'apt|dpkg' | awk '{print $1}' || true)
if [ -n "$pids" ]; then
  for p in $pids; do
    _warn "Killing PID $p"
    kill -9 "$p" >/dev/null 2>&1 || true
  done
else
  _info "No apt/dpkg helper processes found"
fi

# 2) remove known lockfiles
locks=(/var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock)
for l in "${locks[@]}"; do
  if [ -e "$l" ]; then
    _warn "Removing lock: $l"
    rm -f "$l" || true
  fi
done

# 3) dpkg configure & apt -f
_info "Running dpkg --configure -a"
set +e
dpkg --configure -a >> "$LOG" 2>&1
rc=$?
set -e
if [ $rc -eq 0 ]; then _ok "dpkg --configure -a OK"; else _warn "dpkg --configure -a rc=$rc"; fi

_info "Running apt-get install -f -y"
set +e
apt-get install -f -y >> "$LOG" 2>&1 || true
set -e

# 4) Rebuild apt lists with safe mirror rotation
_info "Rebuilding apt lists (mirror rotation)"
codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
FALLBACK=( "http://archive.ubuntu.com/ubuntu/" "http://ports.ubuntu.com/ubuntu/" "http://security.ubuntu.com/ubuntu/" )
success_update=1
for m in "${FALLBACK[@]}"; do
  _info "Trying mirror: $m"
  cat > /etc/apt/sources.list <<EOF
deb ${m} ${codename} main universe restricted multiverse
deb ${m} ${codename}-updates main universe restricted multiverse
deb ${m} ${codename}-security main universe restricted multiverse
EOF
  set +e
  apt-get update -o Acquire::Retries=3 >> "$LOG" 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    _ok "apt-get update OK with $m"
    success_update=0
    break
  else
    _warn "apt-get update failed with mirror $m (rc=$rc)"
  fi
done

if [ $success_update -ne 0 ]; then
  _warn "apt-get update failed for all fallback mirrors. Continuing best-effort."
fi

# 5) optionally collect and wget fallback if apt can't install important packages
APT_CORE=(python3 python3-venv python3-minimal python3-distutils python3-dev build-essential libssl-dev libffi-dev wget apt-transport-https ca-certificates gnupg lsb-release)
_info "Attempting apt-get install --reinstall of core packages"
set +e
apt-get install --reinstall -y "${APT_CORE[@]}" >> "$LOG" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
  _warn "Reinstall returned rc=$rc; attempting wget fallback for packages"
  tmpdir=$(mktemp -d -t aiagent-deb-XXXX)
  uris="$tmpdir/uris.txt"
  touch "$uris"
  for p in "${APT_CORE[@]}"; do
    _info "Collecting URIs for $p"
    set +e
    apt-get --print-uris install -y --allow-unauthenticated "$p" 2>>"$LOG" | awk -F"'" '/http/ {print $2}' >> "$uris"
    set -e
  done
  if [ -s "$uris" ]; then
    _info "Downloading .debs via wget"
    while read -r url; do
      [ -z "$url" ] && continue
      f="$tmpdir/$(basename "$url")"
      wget --tries=3 --timeout=30 -q -O "$f" "$url" || true
    done < "$uris"
    _info "Installing downloaded debs"
    set +e
    dpkg -i "$tmpdir"/*.deb >> "$LOG" 2>&1 || true
    apt-get install -f -y >> "$LOG" 2>&1 || true
    set -e
    rm -rf "$tmpdir" || true
  else
    _warn "No URIs discovered for wget fallback"
  fi
else
  _ok "Reinstalled core packages via apt"
fi

# 6) Recreate venv safely (backup then recreate)
VENV_PATH="/opt/ai-agent/venv"
if [ -d "$VENV_PATH" ]; then
  _info "Backing up existing venv"
  bak="/opt/ai-agent-backups/venv.bak.$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$(dirname "$bak")"
  cp -a "$VENV_PATH" "$bak" || true
  _info "Removing old venv"
  rm -rf "$VENV_PATH" || true
fi
_info "Creating venv at $VENV_PATH"
set +e
python3 -m venv "$VENV_PATH" >> "$LOG" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
  _warn "venv creation failed (rc=$rc); skipping pip installs"
else
  _info "Upgrading pip setuptools wheel inside venv"
  "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel >> "$LOG" 2>&1 || true
  req="/opt/ai-agent/requirements.txt"
  if [ -f "$req" ]; then
    _info "Installing project requirements from $req"
    "$VENV_PATH/bin/pip" install --no-cache-dir -r "$req" >> "$LOG" 2>&1 || { _warn "pip install reported errors"; }
  else
    _warn "No requirements.txt found at $req"
  fi
fi

# 7) systemd units check - do safe enable/start if present
APP_SVC="aiagent-app.service"
WORKER_SVC="aiagent-rq.service"
_info "Checking systemd units"
for svc in "$APP_SVC" "$WORKER_SVC"; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    _info "Unit $svc exists; enabling and restarting"
    systemctl daemon-reload >> "$LOG" 2>&1 || true
    systemctl enable --now "$svc" >> "$LOG" 2>&1 || _warn "Enable/start $svc returned non-zero"
  else
    _warn "Unit $svc missing; skip (use --repair-systemd to auto-generate)"
  fi
done

# 8) final verification: simple checks
_info "Final verification: dpkg, venv, services"
if dpkg -l >/dev/null 2>&1; then _ok "dpkg database accessible"; else _warn "dpkg may be corrupted"; fi
if [ -x "$VENV_PATH/bin/python" ]; then _ok "venv python present"; else _warn "venv python missing"; fi
for svc in "$APP_SVC" "$WORKER_SVC"; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    if systemctl is-active --quiet "$svc"; then _ok "$svc active"; else _warn "$svc inactive"; fi
  fi
done

echo "[$(date --iso-8601=seconds)] Emergency repair finished" >> "$LOG"
echo "Emergency repair complete. Inspect $LOG for details."
exit 0
EOF

chmod +x "$ROOT/tools/emergency-total-repair.sh"

############
# installer wrapper (compact but robust)
############
mkdir -p "$ROOT/install"

cat > "$ROOT/install/install_recursive_safe.sh" <<'EOF'
#!/usr/bin/env bash
# install/install_recursive_safe.sh - compact wrapper that delegates to emergency repair on failure
set -euo pipefail
LOG="/var/log/ai-agent-install-recursive.log"
echo "Installer wrapper starting" | tee -a "$LOG"

TOOLS="$(cd "$(dirname "$0")/.." && pwd)/tools"
EMER="$TOOLS/emergency-total-repair.sh"

# ensure apt update with retries; call emergency repair if stuck
if ! DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=3 >> "$LOG" 2>&1; then
  echo "apt-get update failed; invoking emergency repair (local)" | tee -a "$LOG"
  if [ -x "$EMER" ]; then
    "$EMER" || true
  else
    echo "Emergency tool missing: $EMER" | tee -a "$LOG"
  fi
  DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=3 >> "$LOG" 2>&1 || true
fi

# install minimal set
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip build-essential git curl rsync wget gnupg lsb-release >> "$LOG" 2>&1 || true
echo "Base apt install attempted (check log $LOG)" | tee -a "$LOG"

# attempt to create venv if not exists
TARGET="/opt/ai-agent"
VENV="$TARGET/venv"
if [ ! -d "$VENV" ]; then
  mkdir -p "$TARGET"
  python3 -m venv "$VENV" >> "$LOG" 2>&1 || true
  "$VENV/bin/pip" install --upgrade pip setuptools wheel >> "$LOG" 2>&1 || true
fi

echo "Installer wrapper finished" | tee -a "$LOG"
exit 0
EOF

chmod +x "$ROOT/install/install_recursive_safe.sh"

############
# backend_snippets/healthz_flask.py
############
mkdir -p "$ROOT/backend_snippets"

cat > "$ROOT/backend_snippets/healthz_flask.py" <<'EOF'
# Minimal Flask health endpoint (add this blueprint to your Flask app)
from flask import Blueprint, jsonify
health = Blueprint('health', __name__)
@health.route('/healthz', methods=['GET'])
def healthz():
    return jsonify({"status":"ok"}), 200

# Register in your app:
# from backend_snippets.healthz_flask import health
# app.register_blueprint(health)
EOF

############
# GitHub Actions skeleton
############
mkdir -p "$ROOT/github_actions"
cat > "$ROOT/github_actions/ci_cd_k8s.yaml" <<'EOF'
name: CI/CD Helm Deploy
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 18
      - name: Build frontend
        run: |
          cd frontend
          npm ci
          npm run build
  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy Helm charts
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG }}
        run: |
          helm upgrade --install aiagent-web devops/helm/aiagent-web --namespace aiagent --create-namespace
EOF

############
# smoke tests
############
mkdir -p "$ROOT/smoke_tests"
cat > "$ROOT/smoke_tests/smoke_check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Smoke check: python3 present?"
python3 --version || exit 1
if [ -f ./venv/bin/python ]; then
  ./venv/bin/python -c "import sys; print('venv ok', sys.version)"
else
  echo "No venv in current folder for local smoke; skip"
fi
echo "Smoke checks done"
EOF
chmod +x "$ROOT/smoke_tests/smoke_check.sh"

############
# README + LICENSE
############
cat > "$ROOT/README.md" <<'EOF'
AI Agent bundle - generated
This archive contains:
- frontend/ (React/Tailwind skeleton)
- devops/helm/ (tiny Helm charts)
- tools/emergency-total-repair.sh (advanced repair script)
- install/install_recursive_safe.sh (installer wrapper)
- backend_snippets/healthz_flask.py (Flask health route)
- github_actions/ (CI/CD skeleton)
- smoke_tests/ (basic checks)

Usage notes:
- Inspect scripts before running on production systems.
- Customize values (image repos, domain names, paths).
- Build frontend: cd frontend && npm ci && npm run build
- To attempt local emergency repair (review first):
    sudo bash tools/emergency-total-repair.sh
EOF

cat > "$ROOT/LICENSE.txt" <<'EOF'
Bundle generated by user instruction. Inspect all scripts and use at your own risk. Do not run these scripts on production systems without review.
EOF

############
# Packaging: tar.gz + zip (zip fallback to python if zip missing)
############
tar -czf "$OUT_TAR" "$ROOT"
if command -v zip >/dev/null 2>&1; then
  (cd "$(dirname "$ROOT")" && zip -r "$(basename "$OUT_ZIP")" "$ROOT") >/dev/null 2>&1 || true
else
  # use python to create zip
  python3 - <<PY -c
import zipfile,os
root='${ROOT}'
zf='${OUT_ZIP}'
with zipfile.ZipFile(zf,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for base,dirs,files in os.walk(root):
        for f in files:
            full=os.path.join(base,f)
            arc=os.path.relpath(full, start=os.path.dirname(root))
            z.write(full, arc)
print("zip created")
PY
fi

echo ">>> Bundle created: ${OUT_TAR} and ${OUT_ZIP}"
echo ">>> Directory: ${ROOT}"
echo ">>> Scripts made executable: tools/emergency-total-repair.sh install/install_recursive_safe.sh smoke_tests/smoke_check.sh"
echo "Inspect the bundle directory before running any script on production systems."

