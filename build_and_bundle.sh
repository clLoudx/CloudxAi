#!/usr/bin/env bash
# build_and_bundle.sh
# Build frontend, build docker images, export aiagent_bundle/
set -euo pipefail

SELF="$(realpath "$0")"
ROOT_DIR="$(dirname "$SELF")"
BUNDLE_DIR="${ROOT_DIR}/aiagent_bundle"
FRONTEND_DIR="${ROOT_DIR}/frontend"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${ROOT_DIR}/logs/build_and_bundle_${TIMESTAMP}.log"
mkdir -p "$BUNDLE_DIR" "$ROOT_DIR/logs"

log(){ echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }
err(){ echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG" >&2; exit 1; }

log "Starting build_and_bundle in $ROOT_DIR"

# 1) Build frontend
if [ -d "$FRONTEND_DIR" ] && [ -f "$FRONTEND_DIR/package.json" ]; then
  log "Building frontend..."
  pushd "$FRONTEND_DIR" >/dev/null
  if command -v pnpm >/dev/null 2>&1; then
    pnpm install --silent || true
    pnpm run build || true
  elif command -v yarn >/dev/null 2>&1; then
    yarn install --frozen-lockfile || true
    yarn build || true
  else
    npm ci || npm install || true
    npm run build || true
  fi
  popd >/dev/null
  log "Frontend build finished (check $FRONTEND_DIR/dist or build)"
else
  log "No frontend dir/package.json found — skipping frontend build"
fi

# 2) Build docker images (if Dockerfile present)
BUILD_IMAGES=()
if [ -f "${ROOT_DIR}/Dockerfile" ]; then BUILD_IMAGES+=("web:aiagent_web"); fi
if [ -f "${ROOT_DIR}/Dockerfile.worker" ]; then BUILD_IMAGES+=("worker:aiagent_worker"); fi

if [ ${#BUILD_IMAGES[@]} -gt 0 ]; then
  if ! command -v docker >/dev/null 2>&1; then err "docker not installed — cannot build images"; fi
  for im in "${BUILD_IMAGES[@]}"; do
    part=(${im//:/ })
    typ="${part[0]}"
    tag="${part[1]}"
    log "Building image $tag from Dockerfile.${typ}"
    if [ "$typ" = "web" ]; then
      docker build -f Dockerfile -t "$tag:latest" "$ROOT_DIR" >> "$LOG" 2>&1 || err "docker build web failed"
    else
      docker build -f Dockerfile.worker -t "$tag:latest" "$ROOT_DIR" >> "$LOG" 2>&1 || err "docker build worker failed"
    fi
  done
fi

# 3) Save images to bundle
mkdir -p "$BUNDLE_DIR/images"
if docker image inspect aiagent_web:latest >/dev/null 2>&1; then
  log "Saving aiagent_web:latest"
  docker save aiagent_web:latest | gzip > "$BUNDLE_DIR/images/aiagent_web_latest.tar.gz"
fi
if docker image inspect aiagent_worker:latest >/dev/null 2>&1; then
  log "Saving aiagent_worker:latest"
  docker save aiagent_worker:latest | gzip > "$BUNDLE_DIR/images/aiagent_worker_latest.tar.gz"
fi

# 4) Copy config & systemd templates
mkdir -p "$BUNDLE_DIR/config" "$BUNDLE_DIR/systemd"
cp -a "$ROOT_DIR"/deploy  "$BUNDLE_DIR/" 2>/dev/null || true
cp -a "$ROOT_DIR"/devops "$BUNDLE_DIR/" 2>/dev/null || true
[ -f "$ROOT_DIR/aiagent_full_power_installer.sh" ] && cp "$ROOT_DIR/aiagent_full_power_installer.sh" "$BUNDLE_DIR/" || true

# 5) Build tarball
tar -C "$BUNDLE_DIR" -czf "${BUNDLE_DIR}/aiagent_bundle_${TIMESTAMP}.tgz" -h . || true
log "Bundle packaged at ${BUNDLE_DIR}/aiagent_bundle_${TIMESTAMP}.tgz"

echo "Build and bundle complete. Log: $LOG"

