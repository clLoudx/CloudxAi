#!/usr/bin/env bash
#
# installer_master.sh — Master installer / deployer / verifier for AI Agent
# - Conservative, idempotent, retrying installer that integrates with local helper scripts.
# - Supports local systemd-based install OR Helm/Kubernetes deploy.
#
# Usage examples:
#   sudo ./installer_master.sh --non-interactive --auto-repair
#   sudo ./installer_master.sh --kube-deploy --kubeconfig ~/.kube/config --namespace aiagent --image-pull-secret my-registry-secret --production-verify "kubectl -n aiagent get all" --non-interactive
#
set -o errexit
set -o nounset
set -o pipefail

##############
# Configuration (tweakable)
##############
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="/var/log/ai-agent-installer-master.log"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec 3>>"$LOGFILE"

TARGET_DIR="/opt/ai-agent"
VENV_DIR="$TARGET_DIR/venv"
AI_USER="aiagent"

# Local helper scripts (expected in repo)
GEN_DEVOPS="$REPO_ROOT/generate_devops_and_files.sh"
BUILD_BUNDLE="$REPO_ROOT/build_and_bundle.sh"
EMERGENCY_TOOL="$REPO_ROOT/tools/emergency-total-repair.sh"
DPKG_REPAIR="$REPO_ROOT/tools/dpkg-emergency-repair.sh"
POST_DEPLOY_SMOKE="$REPO_ROOT/devops/tools/post_deploy_smoke.sh"

# K8s defaults
KUBECONFIG_DEFAULT="${KUBECONFIG:-$HOME/.kube/config}"
KUBEDEPLOY="no"
KUBECONFIG="$KUBECONFIG_DEFAULT"
KUBE_NAMESPACE="aiagent"
IMAGE_PULL_SECRET=""
HELM_VALUES_FILE=""
PRODUCTION_VERIFY_CMD=""
PRODUCTION_VERIFY_RETRY=6

# Modes
NON_INTERACTIVE="no"
DRY_RUN="no"
AUTO_REPAIR="no"
ULTRA_MODE="no"

# Retry tuning
RETRY_BASE=4
RETRY_FACTOR=2
RETRY_MAX=120
APT_TIMEOUT=120
PIP_RETRIES=3

# APT packages that may be used (D)
ALL_APT_PACKAGES=(python3 python3-venv python3-pip build-essential python3-dev libffi-dev libssl-dev git curl ca-certificates netcat unzip rsync wget gnupg lsb-release jq apt-transport-https software-properties-common docker.io)

# Colors
RED="\033[1;31m" GREEN="\033[1;32m" YELLOW="\033[1;33m" BLUE="\033[1;34m" NC="\033[0m"
info(){ printf "${BLUE}➤${NC} %s\n" "$*"; echo "INFO: $*" >&3; }
ok(){ printf "${GREEN}✔${NC} %s\n" "$*"; echo "OK: $*" >&3; }
warn(){ printf "${YELLOW}⚠${NC} %s\n" "$*" >&3; }
err(){ printf "${RED}✘${NC} %s\n" "$*" >&3; }

# Helpers
run_cmd(){
  if [ "$DRY_RUN" = "yes" ]; then info "[DRY-RUN] $*"; return 0; fi
  echo "CMD> $*" >&3
  eval "$@"
}

confirm(){
  if [ "$NON_INTERACTIVE" = "yes" ]; then return 0; fi
  read -p "$1 [y/N]: " yn
  [[ "$yn" =~ ^[Yy]$ ]]
}

retry_forever(){
  local cmd="$*"
  local delay=$RETRY_BASE
  local attempt=0
  while true; do
    attempt=$((attempt+1))
    echo "Attempt #$attempt: $cmd" >&3
    if eval "$cmd"; then
      echo "Success: $cmd" >&3
      return 0
    fi
    warn "Command failed (attempt $attempt). Sleeping ${delay}s and retrying..."
    sleep "$delay"
    delay=$((delay * RETRY_FACTOR))
    [ $delay -gt $RETRY_MAX ] && delay=$RETRY_MAX
  done
}

retry_limited(){
  local max="$1"; shift
  local cmd="$*"
  local attempt=0
  local delay=$RETRY_BASE
  while [ $attempt -lt "$max" ]; do
    attempt=$((attempt+1))
    echo "Limited attempt #$attempt: $cmd" >&3
    if eval "$cmd"; then return 0; fi
    warn "Attempt #$attempt failed; sleeping ${delay}s"
    sleep $delay
    delay=$((delay * RETRY_FACTOR))
    [ $delay -gt $RETRY_MAX ] && delay=$RETRY_MAX
  done
  return 1
}

save_snapshot(){
  local out="/var/log/ai-agent-installer-snapshot-$(date +%Y%m%d_%H%M%S).json"
  jq -n \
    --arg ts "$(date --iso-8601=seconds)" \
    --arg root "$REPO_ROOT" \
    --arg target "$TARGET_DIR" \
    --arg venv "$VENV_DIR" \
    --arg arch "$(dpkg --print-architecture 2>/dev/null || uname -m)" \
    '{timestamp:$ts,root:$root,target:$target,venv:$venv,arch:$arch}' > "$out" 2>/dev/null || true
  info "Snapshot saved: $out"
}

# Arg parsing
usage(){
  cat <<EOF
installer_master.sh - master installer & deployer

Usage:
  sudo ./installer_master.sh [options]

Options:
  --kube-deploy               : deploy to Kubernetes via Helm
  --kubeconfig PATH           : kubeconfig path (default: $KUBECONFIG_DEFAULT)
  --namespace NAME            : kubernetes namespace (default: $KUBE_NAMESPACE)
  --image-pull-secret NAME    : imagePullSecret to add to service account
  --helm-values PATH          : extra helm values file
  --production-verify CMD     : command (quoted) to run to verify production (e.g. "kubectl -n aiagent get all")
  --non-interactive
  --dry-run
  --auto-repair               : call emergency repair on failure automatically
  --ultra-mode
  -h, --help                  : show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --kube-deploy) KUBEDEPLOY="yes"; shift;;
    --kubeconfig) KUBECONFIG="$2"; shift 2;;
    --namespace) KUBE_NAMESPACE="$2"; shift 2;;
    --image-pull-secret) IMAGE_PULL_SECRET="$2"; shift 2;;
    --helm-values) HELM_VALUES_FILE="$2"; shift 2;;
    --production-verify) PRODUCTION_VERIFY_CMD="$2"; shift 2;;
    --non-interactive) NON_INTERACTIVE="yes"; shift;;
    --dry-run) DRY_RUN="yes"; shift;;
    --auto-repair) AUTO_REPAIR="yes"; shift;;
    --ultra-mode) ULTRA_MODE="yes"; shift;;
    -h|--help) usage;;
    *) warn "Unknown option: $1"; shift;;
  esac
done

if [ "$ULTRA_MODE" = "yes" ]; then
  RETRY_BASE=6; RETRY_MAX=300; APT_TIMEOUT=180
  info "Ultra mode ON: longer timeouts & retries"
fi

if [ "$(id -u)" -ne 0 ]; then err "Please run as root (sudo)"; exit 1; fi

info "Installer started — log: $LOGFILE"
save_snapshot

##############
# Preflight checks
##############
preflight_checks(){
  title="Preflight checks"
  info "$title"

  # disk space check (>= 2GB)
  avail_kb=$(df --output=avail / | tail -n1 | tr -d ' ')
  if [ "$avail_kb" -lt 2000000 ]; then
    warn "Low disk space: available ${avail_kb} KB (< ~2GB). Continue with caution."
  else
    ok "Disk space OK"
  fi

  # check required commands presence (curl, wget, apt-get)
  missing=()
  for cmd in curl wget apt-get dpkg systemctl rsync python3; do
    if ! command -v $cmd >/dev/null 2>&1; then missing+=("$cmd"); fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing system commands: ${missing[*]} — installer will attempt to install them."
  else
    ok "Core system commands present"
  fi

  # repo helper scripts existence
  local helpers=("$GEN_DEVOPS" "$BUILD_BUNDLE" "$EMERGENCY_TOOL" "$DPKG_REPAIR" "$POST_DEPLOY_SMOKE")
  for f in "${helpers[@]}"; do
    if [ ! -f "$f" ]; then
      warn "Helper missing: $f"
    else
      ok "Helper present: $f"
    fi
  done

  # kube config if kube deploy
  if [ "$KUBEDEPLOY" = "yes" ]; then
    if [ ! -f "$KUBECONFIG" ]; then
      warn "Kubeconfig not found at $KUBECONFIG"
    else
      ok "Kubeconfig found"
    fi
  fi

  # check emergency repair tool is executable
  if [ -f "$EMERGENCY_TOOL" ] && [ ! -x "$EMERGENCY_TOOL" ]; then
    info "Making emergency tool executable: $EMERGENCY_TOOL"
    chmod +x "$EMERGENCY_TOOL" || true
  fi

  ok "Preflight checks completed"
}

##############
# Install apt packages (with retries and dpkg repair)
##############
install_base_packages(){
  info "Installing base system packages: ${ALL_APT_PACKAGES[*]}"
  # first apt-get update with timeout
  set +e
  timeout $APT_TIMEOUT apt-get update >> "$LOGFILE" 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    warn "apt-get update failed (rc=$rc) — trying emergency dpkg repair"
    if [ -x "$DPKG_REPAIR" ]; then
      bash "$DPKG_REPAIR" || true
    else
      warn "dpkg-repair helper not available"
    fi
  fi

  # attempt apt-get install with retries
  if retry_limited 3 "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${ALL_APT_PACKAGES[*]} >> \"$LOGFILE\" 2>&1"; then
    ok "Base packages installed via apt"
    return 0
  fi

  warn "apt-get install failed; attempting dpkg emergency repair and retry"
  if [ -x "$DPKG_REPAIR" ]; then
    bash "$DPKG_REPAIR" || true
  else
    warn "dpkg-repair helper not available"
  fi

  if retry_limited 2 "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${ALL_APT_PACKAGES[*]} >> \"$LOGFILE\" 2>&1"; then
    ok "Base packages installed after repair"
    return 0
  fi

  warn "apt install still failing — will attempt wget fallback if enabled"
  # Collect deb URIs (best effort) and try downloading
  if [ -x "$EMERGENCY_TOOL" ]; then
    info "Delegating python/apt fallback to emergency tool"
    bash "$EMERGENCY_TOOL" --full-auto --wget-fallback --non-interactive || true
  else
    warn "Emergency tool missing for fallback"
  fi

  # final attempt
  if retry_limited 2 "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${ALL_APT_PACKAGES[*]} >> \"$LOGFILE\" 2>&1"; then
    ok "Base packages installed via final attempt"
    return 0
  fi

  err "Failed to install base packages after all attempts"
  return 1
}

##############
# Run repository helper scripts (generate devops, build)
##############
run_local_helpers(){
  info "Running repo helper scripts"

  if [ -f "$GEN_DEVOPS" ] && [ -x "$GEN_DEVOPS" ]; then
    run_cmd bash "$GEN_DEVOPS" || warn "generate_devops failed"
  else
    warn "generate_devops script missing or not executable: $GEN_DEVOPS"
  fi

  if [ -f "$BUILD_BUNDLE" ] && [ -x "$BUILD_BUNDLE" ]; then
    run_cmd bash "$BUILD_BUNDLE" || warn "build_and_bundle failed"
  else
    warn "build_and_bundle script missing or not executable: $BUILD_BUNDLE"
  fi
}

##############
# Install Helm + k8s helper (only if KUBEDEPLOY)
##############
install_helm_and_prereqs(){
  info "Ensuring Helm and kubectl are present"
  if ! command -v helm >/dev/null 2>&1; then
    info "Installing Helm (snap/apt fallback)"
    if command -v snap >/dev/null 2>&1; then
      retry_limited 3 "snap install helm --classic >> \"$LOGFILE\" 2>&1" || true
    else
      # curl install script
      retry_limited 3 "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >> \"$LOGFILE\" 2>&1" || true
    fi
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    info "Installing kubectl binary"
    retry_limited 3 "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl >> \"$LOGFILE\" 2>&1 || true"
    retry_limited 3 "install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl >> \"$LOGFILE\" 2>&1 || true"
  fi
  ok "Helm & kubectl presence ensured (check logs)"
}

##############
# Helm chart deployment (from devops/helm/aiagent - canonical)
##############
helm_deploy_chart(){
  local chart_dir="$REPO_ROOT/devops/helm/aiagent"
  local release_name="aiagent"
  local ns="$KUBE_NAMESPACE"

  if [ ! -d "$chart_dir" ]; then
    err "Chart directory not found: $chart_dir"
  fi

  info "Creating namespace: $ns (if not exists)"
  run_cmd kubectl --kubeconfig "$KUBECONFIG" create namespace "$ns" 2>/dev/null || true

  # ensure imagePull secret if provided
  if [ -n "$IMAGE_PULL_SECRET" ]; then
    info "Linking imagePullSecret: $IMAGE_PULL_SECRET (assumes it already exists in target cluster)"
    # in production you'd create secret from dockerconfig; here we just annotate default SA
    run_cmd kubectl --kubeconfig "$KUBECONFIG" -n "$ns" patch serviceaccount default -p "{\"imagePullSecrets\": [{\"name\": \"$IMAGE_PULL_SECRET\"}]}" || true
  fi

  # build values file: merge provided helm values if any
  local extra_values=""
  if [ -n "$HELM_VALUES_FILE" ] && [ -f "$HELM_VALUES_FILE" ]; then
    extra_values=" -f $HELM_VALUES_FILE"
    info "Using extra Helm values: $HELM_VALUES_FILE"
  fi

  info "Running: helm upgrade --install $release_name $chart_dir -n $ns $extra_values --wait --timeout 10m"
  if ! helm upgrade --install "$release_name" "$chart_dir" -n "$ns" $extra_values --wait --timeout 10m >> "$LOGFILE" 2>&1; then
    err "Helm deploy failed; check $LOGFILE"
    return 1
  fi

  ok "Helm release $release_name deployed to namespace $ns"
  return 0
}

##############
# Wait / check resources and verify production
##############
wait_for_k8s_resources(){
  local ns="$KUBE_NAMESPACE"
  info "Waiting for pods in namespace $ns to be ready (timeout: 600s)"
  local start=$(date +%s)
  local timeout=600
  while true; do
    # count non-ready pods
    notready=$(kubectl --kubeconfig "$KUBECONFIG" -n "$ns" get pods --no-headers 2>/dev/null | awk '{print $1, $2}' | grep -E -v '([0-9]+)/\1' || true)
    if [ -z "$notready" ]; then
      ok "All pods report ready"
      break
    else
      warn "Pods not ready yet:"
      echo "$notready" | sed -n '1,8p'
    fi
    now=$(date +%s)
    if [ $((now-start)) -gt $timeout ]; then
      err "Timeout waiting for pods to be ready"
      return 1
    fi
    sleep 8
  done
  return 0
}

run_production_verify(){
  if [ -z "$PRODUCTION_VERIFY_CMD" ]; then
    warn "No production verify command supplied; skip"
    return 0
  fi
  info "Running production verify: $PRODUCTION_VERIFY_CMD"
  local attempt=1
  local max=$PRODUCTION_VERIFY_RETRY
  local delay=$RETRY_BASE
  while [ $attempt -le $max ]; do
    if eval "$PRODUCTION_VERIFY_CMD" >/dev/null 2>&1; then
      ok "Production verify passed (attempt $attempt)"
      return 0
    fi
    warn "Production verify failed (attempt $attempt). Sleeping $delay.s"
    sleep $delay
    attempt=$((attempt+1)); delay=$((delay * RETRY_FACTOR))
  done
  err "Production verify failed after $max attempts"
  return 1
}

##############
# Run post-deploy smoke test script (local script)
##############
run_post_deploy_smoke(){
  if [ -x "$POST_DEPLOY_SMOKE" ]; then
    info "Running post-deploy smoke tests"
    if [ "$KUBEDEPLOY" = "yes" ]; then
      run_cmd bash "$POST_DEPLOY_SMOKE" "$KUBE_NAMESPACE" "aiagent-web" "/healthz" 8000 || warn "Smoke script reported issues"
    else
      run_cmd bash "$POST_DEPLOY_SMOKE" "local" "aiagent-web" "/healthz" 8000 || warn "Smoke script reported issues"
    fi
  else
    warn "Post-deploy smoke script not found or not executable: $POST_DEPLOY_SMOKE"
  fi
}

##############
# Auto repair wrapper for a failing step
##############
auto_repair_and_retry(){
  local step_name="$1"; shift
  local cmd="$*"

  info "Running step: $step_name"
  set +e
  eval "$cmd"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then ok "Step succeeded: $step_name"; return 0; fi

  warn "Step failed ($step_name) rc=$rc"
  if [ "$AUTO_REPAIR" = "yes" ] || [ "$NON_INTERACTIVE" = "yes" ]; then
    if [ -x "$EMERGENCY_TOOL" ]; then
      info "Running emergency repair tool: $EMERGENCY_TOOL --full-auto --repair-systemd --wget-fallback --self-heal --restart-agent --non-interactive"
      bash "$EMERGENCY_TOOL" --full-auto --repair-systemd --wget-fallback --self-heal --restart-agent --non-interactive || warn "Emergency tool returned non-zero"
    else
      warn "Emergency tool not found for auto repair"
    fi
    info "Retrying step: $step_name"
    set +e
    eval "$cmd"
    rc2=$?
    set -e
    if [ $rc2 -eq 0 ]; then ok "Step fixed after emergency repair: $step_name"; return 0; fi
    err "Step still failing after emergency repair: $step_name"
    return 1
  else
    warn "AUTO_REPAIR disabled — not attempting emergency repair"
    return 1
  fi
}

##############
# Main flow
##############
main(){
  preflight_checks

  # 1) Install base system packages
  auto_repair_and_retry "install_base_packages" install_base_packages

  # 2) Run project-specific helpers to generate devops, build frontend, etc.
  auto_repair_and_retry "run_local_helpers" run_local_helpers

  # 3) If kube deploy requested: install helm prerequisites and deploy chart
  if [ "$KUBEDEPLOY" = "yes" ]; then
    install_helm_and_prereqs
    auto_repair_and_retry "helm_deploy_chart" helm_deploy_chart
    auto_repair_and_retry "wait_for_k8s_resources" wait_for_k8s_resources

    # 4) Run production verification (user-supplied command)
    if [ -n "$PRODUCTION_VERIFY_CMD" ]; then
      auto_repair_and_retry "production_verify" run_production_verify
    fi

    # 5) Run post-deploy smoke
    run_post_deploy_smoke
  else
    # Local/systemd path: create user, venv, systemd units and start services using local helper 'installer.sh'
    info "Non-kube install: ensure target dir present and run local installer if available"

    # create ai user
    if ! id -u "$AI_USER" >/dev/null 2>&1; then
      run_cmd useradd --system --create-home --home-dir /home/"$AI_USER" --shell /usr/sbin/nologin "$AI_USER" || true
    fi

    # run local installer if present
    local_local_installer="$REPO_ROOT/installer.sh"
    if [ -f "$local_local_installer" ] && [ -x "$local_local_installer" ]; then
      auto_repair_and_retry "run_local_installer" "bash \"$local_local_installer\" --non-interactive"
    else
      warn "Local installer missing: $local_local_installer; attempting repair_all helpers"
      auto_repair_and_retry "run_repo_repair_all" "bash \"$REPO_ROOT/aiagent_full_power_installer.sh\" repair || true" || true
    fi

    # run post deploy smoke tests locally
    run_post_deploy_smoke
  fi

  ok "Main install flow complete; final verification follows"

  # Final verification step: call post-deploy smoke again or production verify
  if [ "$KUBEDEPLOY" = "yes" ] && [ -n "$PRODUCTION_VERIFY_CMD" ]; then
    info "Final production verify"
    run_production_verify || warn "Final production verify failed"
  fi

  save_snapshot
  ok "Installer finished. Logs: $LOGFILE"
}

# Run main and catch errors
set +e
main
rc=$?
set -e
if [ $rc -ne 0 ]; then
  err "Installer encountered errors (rc=$rc)."
  warn "Attempting to call emergency repair tool because installer failed."
  if [ -x "$EMERGENCY_TOOL" ]; then
    bash "$EMERGENCY_TOOL" --full-auto --repair-systemd --wget-fallback --self-heal --restart-agent --non-interactive || warn "Emergency tool failed"
  else
    warn "Emergency tool not found: $EMERGENCY_TOOL"
  fi
  exit $rc
fi

exit 0

