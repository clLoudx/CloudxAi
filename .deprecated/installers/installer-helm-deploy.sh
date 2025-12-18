#!/usr/bin/env bash
# installer-helm-deploy.sh
# Installs kubectl/helm, optional infra (ingress-nginx, cert-manager, redis) and deploys helm/aiagent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/helm/aiagent"
RELEASE_NAME="aiagent"
NAMESPACE="aiagent"
NON_INTERACTIVE=no
NO_WAIT=no

usage(){
  cat <<EOF
Usage: sudo $0 [--non-interactive] [--no-wait] [--namespace NAME] [--release NAME]
Env:
  KUBECONFIG is used if set; otherwise default kube config.
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=yes; shift;;
    --no-wait) NO_WAIT=yes; shift;;
    --namespace) NAMESPACE="$2"; shift 2;;
    --release) RELEASE_NAME="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown: $1"; usage;;
  esac
done

confirm_or_exit(){
  if [ "$NON_INTERACTIVE" = "yes" ]; then return 0; fi
  read -p "$1 [y/N]: " yn
  case "$yn" in [Yy]*) return 0;; *) echo "Aborted"; exit 1;; esac
}

log(){ echo "==> $*"; }

# Must be run with a user that has kubectl access to cluster
if ! command -v kubectl >/dev/null 2>&1; then
  log "kubectl missing — installing..."
  # install kubectl (stable method)
  curl -fsSL https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
  log "kubectl installed"
else
  log "kubectl present: $(kubectl version --client --short 2>/dev/null || true)"
fi

if ! command -v helm >/dev/null 2>&1; then
  log "helm missing — installing..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log "helm installed: $(helm version --short 2>/dev/null || true)"
else
  log "helm present: $(helm version --short 2>/dev/null || true)"
fi

# Create namespace if missing
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  log "Creating namespace $NAMESPACE"
  kubectl create namespace "$NAMESPACE"
else
  log "Namespace $NAMESPACE exists"
fi

# Install ingress-nginx (if not present)
if ! kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
  log "Installing ingress-nginx via Helm in namespace ingress-nginx"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --wait --timeout 10m
else
  log "ingress-nginx already installed"
fi

# Install cert-manager (if not present)
if ! kubectl get deployment -n cert-manager cert-manager >/dev/null 2>&1; then
  log "Installing cert-manager"
  # apply CRDs
  kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true --wait --timeout 10m
else
  log "cert-manager already installed"
fi

# Install Redis (Bitnami) into target namespace if not present
if ! kubectl get statefulset -n "$NAMESPACE" aiagent-redis-master >/dev/null 2>&1 && ! kubectl get deployment -n "$NAMESPACE" aiagent-redis-master >/dev/null 2>&1; then
  log "Installing Redis (Bitnami) into namespace $NAMESPACE"
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
  helm upgrade --install aiagent-redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --set auth.enabled=false \
    --wait --timeout 10m
else
  log "Redis appears installed in $NAMESPACE"
fi

# Ensure chart exists
if [ ! -d "$CHART_DIR" ]; then
  echo "ERROR: Helm chart directory not found at $CHART_DIR"
  exit 2
fi

# Package chart to local temp (ensures chart dependencies are tidy)
tmpdir=$(mktemp -d)
log "Packaging Helm chart"
helm dependency update "$CHART_DIR" || true
helm package "$CHART_DIR" -d "$tmpdir"
chartpkg=$(ls "$tmpdir"/*.tgz | head -n1)

if [ -z "$chartpkg" ]; then
  echo "ERROR: chart package not produced"
  exit 3
fi

# Apply production values if present
values_arg=""
if [ -f "$CHART_DIR/values-production.yaml" ]; then
  values_arg="--values $CHART_DIR/values-production.yaml"
  log "Using values-production.yaml for deploy"
fi

wait_flag="--wait"
if [ "$NO_WAIT" = "yes" ]; then wait_flag=""; fi

log "Deploying Helm chart $chartpkg to namespace $NAMESPACE as release $RELEASE_NAME"
helm upgrade --install "$RELEASE_NAME" "$chartpkg" --namespace "$NAMESPACE" $values_arg $wait_flag --timeout 10m

log "Deployment issued. Showing status in namespace $NAMESPACE"
kubectl get all -n "$NAMESPACE" || true

log "Installer script finished."

