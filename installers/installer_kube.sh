#!/usr/bin/env bash
#
# installers/installer_kube.sh — Kubernetes/Helm Deployment Installer
#
# Responsibilities:
#   - Install cert-manager (if missing)
#   - Install ingress-nginx (if missing)
#   - Install Redis (via Helm)
#   - Deploy AI-Agent Helm chart
#   - Run post-deploy smoke tests
#
# This is a focused Kubernetes installer with NO local/systemd logic.
# Called by installer_master.sh for kube mode.
#
# Usage:
#   ./installer_kube.sh --kubeconfig ~/.kube/config --namespace aiagent --image-pull-secret my-secret --helm-values path

set -euo pipefail

###########################################################
# Resolve root repo directory deterministically
###########################################################
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

###########################################################
# Defaults
###########################################################
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NAMESPACE="${NAMESPACE:-aiagent}"
IMAGE_PULL_SECRET="${IMAGE_PULL_SECRET:-}"
HELM_VALUES_FILE="${HELM_VALUES_FILE:-}"

###########################################################
# Import helper modules
###########################################################
if [ -f "$REPO_ROOT/ai-agent/modules/ui.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO_ROOT/ai-agent/modules/ui.sh"
else
    info(){ echo "[INFO] $*"; }
    ok(){ echo "[OK] $*"; }
    warn(){ echo "[WARN] $*"; }
    err(){ echo "[ERR] $*" >&2; }
fi

###########################################################
# Parse arguments
###########################################################
while [ $# -gt 0 ]; do
    case "$1" in
        --kubeconfig) KUBECONFIG="$2"; shift 2;;
        --namespace) NAMESPACE="$2"; shift 2;;
        --image-pull-secret) IMAGE_PULL_SECRET="$2"; shift 2;;
        --helm-values) HELM_VALUES_FILE="$2"; shift 2;;
        --help) 
            echo "Usage: $0 [--kubeconfig PATH] [--namespace NAME] [--image-pull-secret NAME] [--helm-values PATH]"
            exit 0;;
        *) warn "Unknown option: $1"; shift;;
    esac
done

###########################################################
# Preconditions
###########################################################
title "AI-Agent Kubernetes Installer"

# Check required commands
set +e
command -v kubectl >/dev/null 2>&1 || { err "kubectl missing"; exit 1; }
command -v helm >/dev/null 2>&1 || { err "helm missing"; exit 1; }
set -e

if [ ! -f "$KUBECONFIG" ]; then
    warn "Kubeconfig not found at $KUBECONFIG"
fi

###########################################################
# Create namespace
###########################################################
title "Ensuring namespace: $NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" create namespace "$NAMESPACE" 2>/dev/null || true
ok "Namespace $NAMESPACE ready"

###########################################################
# Install cert-manager (if missing)
###########################################################
title "Installing cert-manager (if missing)"
if ! kubectl --kubeconfig "$KUBECONFIG" -n cert-manager get deployment cert-manager >/dev/null 2>&1; then
    info "Adding jetstack Helm repository"
    helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    info "Installing cert-manager"
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager --create-namespace \
        --set installCRDs=true \
        --wait --timeout 5m || warn "cert-manager installation had issues"
    ok "cert-manager installed"
else
    ok "cert-manager already installed"
fi

###########################################################
# Install ingress-nginx (if missing)
###########################################################
title "Installing ingress-nginx (if missing)"
if ! kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; then
    info "Adding ingress-nginx Helm repository"
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    info "Installing ingress-nginx"
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx --create-namespace \
        --wait --timeout 5m || warn "ingress-nginx installation had issues"
    ok "ingress-nginx installed"
else
    ok "ingress-nginx already installed"
fi

###########################################################
# Install Redis (via Helm bitnami)
###########################################################
title "Installing Redis (Helm bitnami)"
info "Adding bitnami Helm repository"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

info "Installing Redis in namespace $NAMESPACE"
helm upgrade --install aiagent-redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --wait --timeout 5m || warn "Redis installation had issues"
ok "Redis installed"

###########################################################
# Prepare imagePullSecret (if provided)
###########################################################
if [ -n "$IMAGE_PULL_SECRET" ]; then
    title "Linking imagePullSecret: $IMAGE_PULL_SECRET"
    kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" patch serviceaccount default \
        -p "{\"imagePullSecrets\":[{\"name\":\"$IMAGE_PULL_SECRET\"}]}" || warn "Failed to patch serviceaccount"
    ok "imagePullSecret linked"
fi

###########################################################
# Deploy AI-Agent Helm chart
###########################################################
title "Deploying AI-Agent Helm chart"
CHART_DIR="$REPO_ROOT/devops/helm/aiagent"

if [ ! -d "$CHART_DIR" ]; then
    err "Chart directory not found: $CHART_DIR"
    exit 1
fi

EXTRA_VALUES=""
if [ -n "$HELM_VALUES_FILE" ] && [ -f "$HELM_VALUES_FILE" ]; then
    EXTRA_VALUES="-f $HELM_VALUES_FILE"
    info "Using extra Helm values: $HELM_VALUES_FILE"
fi

info "Running: helm upgrade --install aiagent $CHART_DIR -n $NAMESPACE $EXTRA_VALUES --wait --timeout 10m"
if helm upgrade --install aiagent "$CHART_DIR" -n "$NAMESPACE" $EXTRA_VALUES --wait --timeout 10m; then
    ok "Helm deployment successful"
else
    err "Helm deployment failed"
    exit 1
fi

###########################################################
# Wait for rollout
###########################################################
title "Waiting for deployment rollout"
kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" rollout status deploy -l app.kubernetes.io/name=aiagent --timeout=600s || warn "Rollout status check had issues"
ok "Deployment rollout complete"

###########################################################
# Post-deploy smoke tests
###########################################################
title "Running post-deploy smoke tests"
if [ -f "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" ]; then
    bash "$REPO_ROOT/devops/tools/post_deploy_smoke.sh" "$NAMESPACE" "aiagent-web" "/healthz" 8000 120 || warn "Smoke tests reported issues"
else
    warn "post_deploy_smoke.sh not found"
fi

###########################################################
# Wrap-up
###########################################################
ok "Kubernetes installation complete."
info "Namespace: $NAMESPACE"
info "Chart: $CHART_DIR"

exit 0

